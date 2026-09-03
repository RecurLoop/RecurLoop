// ============================================================================
// RecurLoop Application Benchmark — Exchange Matching Engine
//
// A deterministic, single-file limit-order-book simulation.
//
// The benchmark intentionally exercises application-shaped workloads rather
// than one isolated numeric kernel:
//   - records and namespaced methods
//   - pointers and pointer arrays
//   - malloc/free and deterministic ownership
//   - sorted insertion with memory movement
//   - matching loops with branch-heavy control flow
//   - function values / indirect strategy calls
//   - pseudo-random synthetic traffic
//   - cancellation and book maintenance
//   - invariant validation and deterministic checksums
//   - standalone executable emission
//
// Build:
//   make example EXAMPLE=06-benchmarks/exchange-simulator BUILD_TYPE=Release
//
// Run:
//   /tmp/recurloop-exchange-sim
//   /tmp/recurloop-exchange-sim 100000
//   /tmp/recurloop-exchange-sim 250000 1 12345
//
// Arguments:
//   argv[1] = number of generated events (default: 50000)
//   argv[2] = pricing strategy: 0=mean-revert, 1=momentum (default: 0)
//   argv[3] = deterministic RNG seed (default: 1337)
//
// This is not intended to model a production exchange exactly. It is a
// reproducible systems benchmark with realistic state transitions.
// ============================================================================


// ============================================================================
// Runtime support
// ============================================================================

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64


// ============================================================================
// Small utility namespace
// ============================================================================

let Util = []

let Util:parse_i64 = fn (text:u8*) -> i64 {
    var i = 0
    var sign = 1
    var value = 0

    if text[0] == 45 {
        sign = -1
        i = 1
    }

    while text[i] >= 48 && text[i] <= 57 {
        value = value * 10 + text[i] - 48
        i += 1
    }

    return value * sign
}

let Util:min = fn (left:i64, right:i64) -> i64 {
    if left < right {
        return left
    }
    return right
}

let Util:abs = fn (value:i64) -> i64 {
    if value < 0 {
        return -value
    }
    return value
}


// ============================================================================
// Deterministic pseudo-random generator
//
// Park-Miller LCG. Keeping it deliberately simple makes the benchmark result
// reproducible across runs and keeps RNG cost visible rather than hidden in a
// library call.
// ============================================================================

let Rng = []

let Rng:next = fn (state:i64*) -> i64 {
    var next = (state[0] * 48271) % 2147483647
    if next <= 0 {
        next += 2147483646
    }
    state[0] = next
    return next
}


// ============================================================================
// Domain model
// ============================================================================

record Order {
    id:i64
    side:i64
    price:i64
    quantity:i64
    remaining:i64
    sequence:i64
}

record ExchangeStats {
    submitted:i64
    accepted:i64
    rejected:i64
    cancelled:i64
    trades:i64
    volume:i64
    notional:i64
    validations:i64
    checksum:i64
}

record OrderBook {
    capacity:i64
    bid_count:i64
    ask_count:i64
    bids:Order**
    asks:Order**
    next_id:i64
    sequence:i64
    last_price:i64
    stats:ExchangeStats*
}


// ============================================================================
// Order lifecycle
// ============================================================================

let Order:new = fn (id:i64, side:i64, price:i64, quantity:i64, sequence:i64) -> Order* {
    var order:Order* = cast(Order*, malloc(48))
    order.id = id
    order.side = side
    order.price = price
    order.quantity = quantity
    order.remaining = quantity
    order.sequence = sequence
    return order
}

let Order:destroy = fn (self:Order*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Order:filled = fn (self:Order*) -> i64 {
    if self.remaining == 0 {
        return 1
    }
    return 0
}


// ============================================================================
// Statistics lifecycle
// ============================================================================

let ExchangeStats:new = fn () -> ExchangeStats* {
    var stats:ExchangeStats* = cast(ExchangeStats*, malloc(72))
    stats.submitted = 0
    stats.accepted = 0
    stats.rejected = 0
    stats.cancelled = 0
    stats.trades = 0
    stats.volume = 0
    stats.notional = 0
    stats.validations = 0
    stats.checksum = 17
    return stats
}

let ExchangeStats:destroy = fn (self:ExchangeStats*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let ExchangeStats:record_trade = fn (self:ExchangeStats*, maker:Order*, taker:Order*, price:i64, quantity:i64) -> i64 {
    self.trades += 1
    self.volume += quantity
    self.notional += price * quantity

    // A stable digest prevents the optimizer from treating the simulation as
    // dead work and also gives us a deterministic regression signal.
    var digest = self.checksum * 131
    digest += maker.id * 17
    digest += taker.id * 19
    digest += price * 23
    digest += quantity * 29
    self.checksum = digest % 2147483647

    return 0
}


// ============================================================================
// Order book lifecycle
// ============================================================================

let OrderBook:new = fn (capacity:i64) -> OrderBook* {
    var book:OrderBook* = cast(OrderBook*, malloc(72))
    book.capacity = capacity
    book.bid_count = 0
    book.ask_count = 0
    book.bids = cast(Order**, malloc(capacity * 8))
    book.asks = cast(Order**, malloc(capacity * 8))
    book.next_id = 1
    book.sequence = 1
    book.last_price = 10000
    book.stats = ExchangeStats:new()
    return book
}

let OrderBook:destroy = fn (self:OrderBook*) -> i64 {
    var i = 0

    while i < self.bid_count {
        Order:destroy(self.bids[i])
        i += 1
    }

    i = 0
    while i < self.ask_count {
        Order:destroy(self.asks[i])
        i += 1
    }

    free(cast(u8*, self.bids))
    free(cast(u8*, self.asks))
    ExchangeStats:destroy(self.stats)
    free(cast(u8*, self))
    return 0
}


// ============================================================================
// Book maintenance
//
// Bids are sorted from highest to lowest price.
// Asks are sorted from lowest to highest price.
// Equal-price orders retain FIFO sequence because insertion only moves entries
// with a strictly worse price.
// ============================================================================

let OrderBook:insert_bid = fn (self:OrderBook*, order:Order*) -> i64 {
    if self.bid_count >= self.capacity {
        return -1
    }

    var i = self.bid_count
    while i > 0 && self.bids[i - 1].price < order.price {
        self.bids[i] = self.bids[i - 1]
        i -= 1
    }

    self.bids[i] = order
    self.bid_count += 1
    return 0
}

let OrderBook:insert_ask = fn (self:OrderBook*, order:Order*) -> i64 {
    if self.ask_count >= self.capacity {
        return -1
    }

    var i = self.ask_count
    while i > 0 && self.asks[i - 1].price > order.price {
        self.asks[i] = self.asks[i - 1]
        i -= 1
    }

    self.asks[i] = order
    self.ask_count += 1
    return 0
}

let OrderBook:erase_bid_at = fn (self:OrderBook*, index:i64) -> i64 {
    var removed = self.bids[index]
    var i = index + 1

    while i < self.bid_count {
        self.bids[i - 1] = self.bids[i]
        i += 1
    }

    self.bid_count -= 1
    Order:destroy(removed)
    return 0
}

let OrderBook:erase_ask_at = fn (self:OrderBook*, index:i64) -> i64 {
    var removed = self.asks[index]
    var i = index + 1

    while i < self.ask_count {
        self.asks[i - 1] = self.asks[i]
        i += 1
    }

    self.ask_count -= 1
    Order:destroy(removed)
    return 0
}


// ============================================================================
// Matching engine
// ============================================================================

let OrderBook:match_buy = fn (self:OrderBook*, incoming:Order*) -> i64 {
    while incoming.remaining > 0 && self.ask_count > 0 {
        var maker = self.asks[0]

        if maker.price > incoming.price {
            return 0
        }

        var traded = Util:min(incoming.remaining, maker.remaining)
        incoming.remaining -= traded
        maker.remaining -= traded
        self.last_price = maker.price

        ExchangeStats:record_trade(self.stats, maker, incoming, maker.price, traded)

        if Order:filled(maker) {
            OrderBook:erase_ask_at(self, 0)
        }
    }

    return 0
}

let OrderBook:match_sell = fn (self:OrderBook*, incoming:Order*) -> i64 {
    while incoming.remaining > 0 && self.bid_count > 0 {
        var maker = self.bids[0]

        if maker.price < incoming.price {
            return 0
        }

        var traded = Util:min(incoming.remaining, maker.remaining)
        incoming.remaining -= traded
        maker.remaining -= traded
        self.last_price = maker.price

        ExchangeStats:record_trade(self.stats, maker, incoming, maker.price, traded)

        if Order:filled(maker) {
            OrderBook:erase_bid_at(self, 0)
        }
    }

    return 0
}

let OrderBook:submit = fn (self:OrderBook*, side:i64, price:i64, quantity:i64) -> i64 {
    self.stats.submitted += 1

    if quantity <= 0 || price <= 0 || (side != 1 && side != -1) {
        self.stats.rejected += 1
        return 0
    }

    // We cap each side independently. This benchmark chooses predictable
    // bounded memory over exchange-specific overflow semantics.
    if side == 1 && self.bid_count >= self.capacity {
        self.stats.rejected += 1
        return 0
    }

    if side == -1 && self.ask_count >= self.capacity {
        self.stats.rejected += 1
        return 0
    }

    var id = self.next_id
    var seq = self.sequence
    self.next_id += 1
    self.sequence += 1
    self.stats.accepted += 1

    var order = Order:new(id, side, price, quantity, seq)

    if side == 1 {
        OrderBook:match_buy(self, order)

        if order.remaining > 0 {
            if OrderBook:insert_bid(self, order) != 0 {
                self.stats.rejected += 1
                Order:destroy(order)
                return 0
            }
        } else {
            Order:destroy(order)
        }
    } else {
        OrderBook:match_sell(self, order)

        if order.remaining > 0 {
            if OrderBook:insert_ask(self, order) != 0 {
                self.stats.rejected += 1
                Order:destroy(order)
                return 0
            }
        } else {
            Order:destroy(order)
        }
    }

    var digest = self.stats.checksum * 31
    digest += id * 7
    digest += side * 11
    digest += price * 13
    digest += quantity * 17
    self.stats.checksum = digest % 2147483647

    if self.stats.checksum < 0 {
        self.stats.checksum = -self.stats.checksum
    }

    return id
}


// ============================================================================
// Cancellation
// ============================================================================

let OrderBook:cancel = fn (self:OrderBook*, id:i64) -> i64 {
    var i = 0

    while i < self.bid_count {
        if self.bids[i].id == id {
            self.stats.checksum = (self.stats.checksum * 37 + id * 41) % 2147483647
            self.stats.cancelled += 1
            OrderBook:erase_bid_at(self, i)
            return 1
        }
        i += 1
    }

    i = 0
    while i < self.ask_count {
        if self.asks[i].id == id {
            self.stats.checksum = (self.stats.checksum * 37 + id * 43) % 2147483647
            self.stats.cancelled += 1
            OrderBook:erase_ask_at(self, i)
            return 1
        }
        i += 1
    }

    return 0
}

let OrderBook:cancel_random = fn (self:OrderBook*, token:i64) -> i64 {
    var total = self.bid_count + self.ask_count
    if total == 0 {
        return 0
    }

    var index = token % total

    if index < self.bid_count {
        return OrderBook:cancel(self, self.bids[index].id)
    }

    index -= self.bid_count
    return OrderBook:cancel(self, self.asks[index].id)
}


// ============================================================================
// Queries
// ============================================================================

let OrderBook:best_bid = fn (self:OrderBook*) -> i64 {
    if self.bid_count == 0 {
        return 0
    }
    return self.bids[0].price
}

let OrderBook:best_ask = fn (self:OrderBook*) -> i64 {
    if self.ask_count == 0 {
        return 0
    }
    return self.asks[0].price
}

let OrderBook:spread = fn (self:OrderBook*) -> i64 {
    if self.bid_count == 0 || self.ask_count == 0 {
        return 0
    }
    return self.asks[0].price - self.bids[0].price
}

let OrderBook:resting_quantity = fn (self:OrderBook*) -> i64 {
    var total = 0
    var i = 0

    while i < self.bid_count {
        total += self.bids[i].remaining
        i += 1
    }

    i = 0
    while i < self.ask_count {
        total += self.asks[i].remaining
        i += 1
    }

    return total
}


// ============================================================================
// Invariant checking
//
// Running this periodically is intentionally part of the benchmark. It adds
// full-book scans and catches corruption immediately during development.
// ============================================================================

let OrderBook:verify = fn (self:OrderBook*) -> i64 {
    if self.bid_count < 0 || self.bid_count > self.capacity {
        return 0
    }

    if self.ask_count < 0 || self.ask_count > self.capacity {
        return 0
    }

    var i = 0
    while i < self.bid_count {
        if self.bids[i].remaining <= 0 {
            return 0
        }

        if i > 0 && self.bids[i - 1].price < self.bids[i].price {
            return 0
        }

        if i > 0 && self.bids[i - 1].price == self.bids[i].price && self.bids[i - 1].sequence > self.bids[i].sequence {
            return 0
        }

        i += 1
    }

    i = 0
    while i < self.ask_count {
        if self.asks[i].remaining <= 0 {
            return 0
        }

        if i > 0 && self.asks[i - 1].price > self.asks[i].price {
            return 0
        }

        if i > 0 && self.asks[i - 1].price == self.asks[i].price && self.asks[i - 1].sequence > self.asks[i].sequence {
            return 0
        }

        i += 1
    }

    // After matching completes there must be no crossed resting market.
    if self.bid_count > 0 && self.ask_count > 0 {
        if self.bids[0].price >= self.asks[0].price {
            return 0
        }
    }

    self.stats.validations += 1
    return 1
}


// ============================================================================
// Pricing strategies
//
// A function value is selected once and then called indirectly for every new
// order. This gives the benchmark an application-level callback hot path.
// ============================================================================

let Strategy = []

let Strategy:mean_revert = fn (event:i64, random:i64, side:i64, last_price:i64) -> i64 {
    var noise = random % 121 - 60
    var anchor = 10000
    var distance = last_price - anchor
    var correction = distance / 8
    var price = last_price + noise - correction

    // Slight taker bias so the book does real matching instead of growing
    // monotonically until capacity.
    if random % 10 < 3 {
        if side == 1 {
            price += 35
        } else {
            price -= 35
        }
    }

    if price < 9000 {
        return 9000
    }
    if price > 11000 {
        return 11000
    }
    return price
}

let Strategy:momentum = fn (event:i64, random:i64, side:i64, last_price:i64) -> i64 {
    var noise = random % 81 - 40
    var wave = event % 400
    var drift = 0

    if wave < 200 {
        drift = 8
    } else {
        drift = -8
    }

    var price = last_price + noise + drift

    if random % 10 < 2 {
        if side == 1 {
            price += 50
        } else {
            price -= 50
        }
    }

    if price < 9000 {
        return 9000
    }
    if price > 11000 {
        return 11000
    }
    return price
}

let Strategy:choose = fn (mode:i64) -> fn (i64, i64, i64, i64) -> i64 {
    if mode == 1 {
        return momentum
    }
    return mean_revert
}


// ============================================================================
// Deterministic self-test
// ============================================================================

let self_test = fn () -> i64 {
    var book = OrderBook:new(16)
    defer OrderBook:destroy(book)

    var score = 0

    var id1 = OrderBook:submit(book, 1, 1000, 10)
    var id2 = OrderBook:submit(book, -1, 1010, 4)
    var id3 = OrderBook:submit(book, -1, 995, 6)
    var id4 = OrderBook:submit(book, 1, 1020, 10)

    if id1 == 1 && id2 == 2 && id3 == 3 && id4 == 4 {
        score += 1
    }

    if book.stats.accepted == 4 {
        score += 1
    }

    if book.stats.trades == 2 {
        score += 1
    }

    if book.stats.volume == 10 {
        score += 1
    }

    if book.stats.notional == 10040 {
        score += 1
    }

    if book.bid_count == 2 {
        score += 1
    }

    if book.ask_count == 0 {
        score += 1
    }

    if OrderBook:best_bid(book) == 1020 {
        score += 1
    }

    if book.bids[0].remaining == 6 {
        score += 1
    }

    if book.last_price == 1010 {
        score += 1
    }

    if OrderBook:cancel(book, id1) == 1 {
        score += 1
    }

    if book.bid_count == 1 {
        score += 1
    }

    if OrderBook:cancel(book, id3) == 0 {
        score += 1
    }

    if OrderBook:verify(book) == 1 {
        score += 1
    }

    return score
}


// ============================================================================
// Synthetic market traffic
// ============================================================================

let seed_liquidity = fn (book:OrderBook*, levels:i64) -> i64 {
    var level = 1

    while level <= levels {
        var quantity = 20 + level % 11

        OrderBook:submit(book, 1, 10000 - level * 3, quantity)
        OrderBook:submit(book, -1, 10000 + level * 3, quantity)

        level += 1
    }

    return 0
}

let run_simulation = fn (book:OrderBook*, events:i64, seed:i64, pricing:fn (i64, i64, i64, i64) -> i64) -> i64 {
    var rng = seed
    if rng <= 0 {
        rng = 1337
    }

    seed_liquidity(book, 64)

    var event = 0
    while event < events {
        var action_random = Rng:next(&rng)
        var action = action_random % 100

        if action < 84 {
            var side_random = Rng:next(&rng)
            var price_random = Rng:next(&rng)
            var quantity_random = Rng:next(&rng)

            var side = 1
            if side_random % 2 == 0 {
                side = -1
            }

            var price = pricing(event, price_random, side, book.last_price)
            var quantity = 1 + quantity_random % 25

            OrderBook:submit(book, side, price, quantity)
        } else {
            OrderBook:cancel_random(book, action_random)
        }

        // Periodic O(n) verification deliberately adds a second workload
        // dimension beyond matching itself.
        if event % 1024 == 0 {
            if OrderBook:verify(book) == 0 {
                return -1
            }
        }

        event += 1
    }

    if OrderBook:verify(book) == 0 {
        return -1
    }

    return book.stats.checksum
}


// ============================================================================
// Human-readable report
// ============================================================================

let print_top = fn (book:OrderBook*, depth:i64) -> i64 {
    printf("\nTop of book\n")
    printf("-----------\n")
    printf("best bid: %lld\n", OrderBook:best_bid(book))
    printf("best ask: %lld\n", OrderBook:best_ask(book))
    printf("spread:   %lld\n", OrderBook:spread(book))
    printf("last:     %lld\n", book.last_price)

    printf("\nBids\n")
    var i = 0
    while i < book.bid_count && i < depth {
        printf("  #%lld price=%lld remaining=%lld seq=%lld\n", book.bids[i].id, book.bids[i].price, book.bids[i].remaining, book.bids[i].sequence)
        i += 1
    }

    printf("\nAsks\n")
    i = 0
    while i < book.ask_count && i < depth {
        printf("  #%lld price=%lld remaining=%lld seq=%lld\n", book.asks[i].id, book.asks[i].price, book.asks[i].remaining, book.asks[i].sequence)
        i += 1
    }

    return 0
}

let print_report = fn (book:OrderBook*, events:i64, strategy:i64, seed:i64) -> i64 {
    printf("\n============================================================\n")
    printf(" RecurLoop Exchange Matching Engine Benchmark\n")
    printf("============================================================\n")
    printf("events:             %lld\n", events)
    printf("strategy:           %lld\n", strategy)
    printf("seed:               %lld\n", seed)
    printf("capacity / side:    %lld\n", book.capacity)

    printf("\nOrder flow\n")
    printf("----------\n")
    printf("submitted:          %lld\n", book.stats.submitted)
    printf("accepted:           %lld\n", book.stats.accepted)
    printf("rejected:           %lld\n", book.stats.rejected)
    printf("cancelled:          %lld\n", book.stats.cancelled)

    printf("\nMatching\n")
    printf("--------\n")
    printf("trades:             %lld\n", book.stats.trades)
    printf("volume:             %lld\n", book.stats.volume)
    printf("notional:           %lld\n", book.stats.notional)

    printf("\nBook state\n")
    printf("----------\n")
    printf("resting bids:       %lld\n", book.bid_count)
    printf("resting asks:       %lld\n", book.ask_count)
    printf("resting quantity:   %lld\n", OrderBook:resting_quantity(book))
    printf("validations:        %lld\n", book.stats.validations)
    printf("checksum:           %lld\n", book.stats.checksum)

    print_top(book, 5)

    printf("\n============================================================\n")
    printf("done\n")
    return 0
}


// ============================================================================
// Standalone application
// ============================================================================

module auto
module clear
module strip
module entry exchange_main

emit executable "/tmp/recurloop-exchange-sim" exchange_main = fn (argc:i64, argv:u8**) -> i64 {
    var events = 50000
    var strategy = 0
    var seed = 1337

    if argc > 1 {
        events = Util:parse_i64(argv[1])
    }

    if argc > 2 {
        strategy = Util:parse_i64(argv[2])
    }

    if argc > 3 {
        seed = Util:parse_i64(argv[3])
    }

    if events <= 0 {
        printf("error: event count must be greater than zero\n")
        return 1
    }

    if strategy != 0 && strategy != 1 {
        printf("error: strategy must be 0 or 1\n")
        return 1
    }

    var test_score = self_test()
    if test_score != 14 {
        printf("self-test failed: %lld/14 checks passed\n", test_score)
        return 2
    }

    printf("self-test: 14/14 checks passed\n")

    var book = OrderBook:new(4096)
    defer OrderBook:destroy(book)

    let pricing:fn (i64, i64, i64, i64) -> i64 = Strategy:choose(strategy)
    var result = run_simulation(book, events, seed, pricing)

    if result < 0 {
        printf("benchmark failed: order-book invariant violation\n")
        return 3
    }

    print_report(book, events, strategy, seed)
    return 0
}

link clear


// ============================================================================
// Compiler / elaborator statistics
// ============================================================================

debug:stats
