// ============================================================================
// RecurLoop Application Benchmark — JSON Processor
//
// A deterministic, single-file JSON parser and analytics workload.
//
// Exercises:
//   - recursive-descent parsing
//   - strings and escape decoding
//   - decimal number parsing into fixed-point i64 (scale 1e4)
//   - records and pointer-heavy trees
//   - malloc/free with recursive ownership
//   - dynamically growing arrays
//   - object lookup and string comparison
//   - recursive traversal and transformations
//   - application-shaped aggregation over commerce data
//   - deterministic checksums
//   - standalone executable emission
//
// Build:
//   make example EXAMPLE=06-benchmarks/json-processor BUILD_TYPE=Release
//
// Run:
//   /tmp/recurloop-json-processor
//   /tmp/recurloop-json-processor 1000
//   /tmp/recurloop-json-processor 5000
//
// argv[1] = parse/process iterations (default: 2000)
// ============================================================================

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64


// ============================================================================
// Text helpers
// ============================================================================

let Text = []

let Text:length = fn (text:u8*) -> i64 {
    var length = 0
    while text[length] != 0 {
        length += 1
    }
    return length
}

let Text:equals = fn (left:u8*, right:u8*) -> i64 {
    var i = 0
    while left[i] != 0 && right[i] != 0 {
        if left[i] != right[i] {
            return 0
        }
        i += 1
    }

    if left[i] == 0 && right[i] == 0 {
        return 1
    }
    return 0
}

let Text:hash = fn (text:u8*) -> i64 {
    var hash = 5381
    var i = 0
    while text[i] != 0 {
        hash = (hash * 33 + text[i] + 1) % 2147483647
        i += 1
    }
    return hash
}

let Text:clone = fn (text:u8*) -> u8* {
    var length = Text:length(text)
    var copy:u8* = cast(u8*, malloc(length + 1))
    var i = 0
    while i < length {
        copy[i] = text[i]
        i += 1
    }
    copy[length] = 0
    return copy
}

let Text:parse_i64 = fn (text:u8*) -> i64 {
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


let Text:append = fn (output:u8*, offset:i64, text:u8*) -> i64 {
    var i = 0
    while text[i] != 0 {
        output[offset] = text[i]
        offset += 1
        i += 1
    }
    output[offset] = 0
    return offset
}

// ============================================================================
// JSON value model
//
// kind:
//   0 = null
//   1 = bool
//   2 = number
//   3 = string
//   4 = array
//   5 = object
// ============================================================================

record JsonValue {
    kind:i64
    number:i64
    boolean:i64
    text:u8*
    text_length:i64
    count:i64
    capacity:i64
    children:u8**
    keys:u8**
}

let JsonValue:new = fn (kind:i64) -> JsonValue* {
    var value:JsonValue* = cast(JsonValue*, malloc(72))
    value.kind = kind
    value.number = 0
    value.boolean = 0
    value.text = cast(u8*, 0)
    value.text_length = 0
    value.count = 0
    value.capacity = 0
    value.children = cast(u8**, 0)
    value.keys = cast(u8**, 0)
    return value
}

let JsonValue:new_null = fn () -> JsonValue* {
    return JsonValue:new(0)
}

let JsonValue:new_bool = fn (boolean:i64) -> JsonValue* {
    var value = JsonValue:new(1)
    value.boolean = boolean
    return value
}

// JSON numbers are stored as signed fixed-point i64 with scale 10000.
// This keeps the standalone benchmark inside the current typed fn backend.
let JsonValue:new_number = fn () -> JsonValue* {
    return JsonValue:new(2)
}

let JsonValue:new_string = fn (text:u8*, length:i64) -> JsonValue* {
    var value = JsonValue:new(3)
    value.text = text
    value.text_length = length
    return value
}

let JsonValue:new_container = fn (kind:i64, initial_capacity:i64) -> JsonValue* {
    var value = JsonValue:new(kind)
    value.capacity = initial_capacity
    value.children = cast(u8**, malloc(initial_capacity * 8))

    if kind == 5 {
        value.keys = cast(u8**, malloc(initial_capacity * 8))
    }

    return value
}

let JsonValue:grow = fn (self:JsonValue*) -> i64 {
    var new_capacity = self.capacity * 2
    if new_capacity < 4 {
        new_capacity = 4
    }

    var new_children:u8** = cast(u8**, malloc(new_capacity * 8))
    var new_keys:u8** = cast(u8**, 0)

    if self.kind == 5 {
        new_keys = cast(u8**, malloc(new_capacity * 8))
    }

    var i = 0
    while i < self.count {
        new_children[i] = self.children[i]
        if self.kind == 5 {
            new_keys[i] = self.keys[i]
        }
        i += 1
    }

    if cast(i64, self.children) != 0 {
        free(cast(u8*, self.children))
    }
    if cast(i64, self.keys) != 0 {
        free(cast(u8*, self.keys))
    }

    self.children = new_children
    self.keys = new_keys
    self.capacity = new_capacity
    return 0
}

let JsonValue:add_array = fn (self:JsonValue*, child:JsonValue*) -> i64 {
    if self.count >= self.capacity {
        JsonValue:grow(self)
    }
    self.children[self.count] = cast(u8*, child)
    self.count += 1
    return 0
}

let JsonValue:add_object = fn (self:JsonValue*, key:u8*, child:JsonValue*) -> i64 {
    if self.count >= self.capacity {
        JsonValue:grow(self)
    }
    self.keys[self.count] = key
    self.children[self.count] = cast(u8*, child)
    self.count += 1
    return 0
}

let JsonValue:get = fn (self:JsonValue*, key:u8*) -> JsonValue* {
    if self.kind != 5 {
        return cast(JsonValue*, 0)
    }

    var i = 0
    while i < self.count {
        if Text:equals(self.keys[i], key) != 0 {
            return cast(JsonValue*, self.children[i])
        }
        i += 1
    }
    return cast(JsonValue*, 0)
}

let JsonValue:destroy = fn (self:JsonValue*) -> i64 {
    if cast(i64, self) == 0 {
        return 0
    }

    if self.kind == 3 {
        if cast(i64, self.text) != 0 {
            free(self.text)
        }
    }

    if self.kind == 4 || self.kind == 5 {
        var i = 0
        while i < self.count {
            JsonValue:destroy(cast(JsonValue*, self.children[i]))
            if self.kind == 5 {
                free(self.keys[i])
            }
            i += 1
        }

        if cast(i64, self.children) != 0 {
            free(cast(u8*, self.children))
        }
        if cast(i64, self.keys) != 0 {
            free(cast(u8*, self.keys))
        }
    }

    free(cast(u8*, self))
    return 0
}


// ============================================================================
// Parser
// ============================================================================

record Parser {
    text:u8*
    length:i64
    position:i64
    nodes:i64
    strings:i64
    errors:i64
}

let Parser:new = fn (text:u8*) -> Parser* {
    var parser:Parser* = cast(Parser*, malloc(48))
    parser.text = text
    parser.length = Text:length(text)
    parser.position = 0
    parser.nodes = 0
    parser.strings = 0
    parser.errors = 0
    return parser
}

let Parser:destroy = fn (self:Parser*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Parser:skip_ws = fn (self:Parser*) -> i64 {
    while self.position < self.length {
        var c = self.text[self.position]
        if c == 32 || c == 9 || c == 10 || c == 13 {
            self.position += 1
        } else {
            return 0
        }
    }
    return 0
}

let Parser:consume = fn (self:Parser*, expected:i64) -> i64 {
    Parser:skip_ws(self)
    if self.position >= self.length {
        self.errors += 1
        return 0
    }
    if self.text[self.position] != expected {
        self.errors += 1
        return 0
    }
    self.position += 1
    return 1
}

let Parser:match_literal = fn (self:Parser*, literal:u8*) -> i64 {
    var i = 0
    while literal[i] != 0 {
        if self.position + i >= self.length {
            return 0
        }
        if self.text[self.position + i] != literal[i] {
            return 0
        }
        i += 1
    }
    self.position += i
    return 1
}

// Decode a JSON string and return an owned, NUL-terminated buffer.
let Parser:parse_string_text = fn (self:Parser*) -> u8* {
    Parser:skip_ws(self)

    if self.position >= self.length || self.text[self.position] != 34 {
        self.errors += 1
        return cast(u8*, 0)
    }

    self.position += 1

    // The decoded string can never be longer than the remaining source.
    var output:u8* = cast(u8*, malloc(self.length - self.position + 1))
    var out = 0
    var done = 0

    while self.position < self.length && done == 0 {
        var c = self.text[self.position]
        self.position += 1

        if c == 34 {
            done = 1
        } else if c == 92 {
            if self.position >= self.length {
                self.errors += 1
                done = 1
            } else {
                var escaped = self.text[self.position]
                self.position += 1

                if escaped == 34 || escaped == 92 || escaped == 47 {
                    output[out] = escaped
                } else if escaped == 98 {
                    output[out] = 8
                } else if escaped == 102 {
                    output[out] = 12
                } else if escaped == 110 {
                    output[out] = 10
                } else if escaped == 114 {
                    output[out] = 13
                } else if escaped == 116 {
                    output[out] = 9
                } else {
                    // \uXXXX is intentionally omitted from this benchmark.
                    // Unsupported escapes are marked as parser errors.
                    self.errors += 1
                    output[out] = 63
                }
                out += 1
            }
        } else {
            output[out] = c
            out += 1
        }
    }

    if done == 0 {
        self.errors += 1
    }

    output[out] = 0
    self.strings += 1
    return output
}

// Flag-based number parser used by parse_value. Kept separate so the hot path
// does not depend on break/continue syntax.
let Parser:number = fn (self:Parser*) -> JsonValue* {
    Parser:skip_ws(self)

    var sign = 1
    if self.text[self.position] == 45 {
        sign = -1
        self.position += 1
    }

    var integer = 0
    var integer_scan = 1
    var digits = 0

    while self.position < self.length && integer_scan != 0 {
        var c = self.text[self.position]
        if c >= 48 && c <= 57 {
            integer = integer * 10 + c - 48
            self.position += 1
            digits += 1
        } else {
            integer_scan = 0
        }
    }

    if digits == 0 {
        self.errors += 1
    }

    var fraction = 0
    var fraction_digits = 0

    if self.position < self.length && self.text[self.position] == 46 {
        self.position += 1
        var fraction_scan = 1

        while self.position < self.length && fraction_scan != 0 {
            var c = self.text[self.position]
            if c >= 48 && c <= 57 {
                if fraction_digits < 4 {
                    fraction = fraction * 10 + c - 48
                    fraction_digits += 1
                }
                self.position += 1
            } else {
                fraction_scan = 0
            }
        }
    }

    while fraction_digits < 4 {
        fraction *= 10
        fraction_digits += 1
    }

    var value = integer * 10000 + fraction

    if self.position < self.length && (self.text[self.position] == 101 || self.text[self.position] == 69) {
        self.position += 1
        var exponent_sign = 1

        if self.text[self.position] == 45 {
            exponent_sign = -1
            self.position += 1
        } else if self.text[self.position] == 43 {
            self.position += 1
        }

        var exponent = 0
        var exponent_scan = 1
        while self.position < self.length && exponent_scan != 0 {
            var c = self.text[self.position]
            if c >= 48 && c <= 57 {
                exponent = exponent * 10 + c - 48
                self.position += 1
            } else {
                exponent_scan = 0
            }
        }

        var e = 0
        if exponent_sign > 0 {
            while e < exponent {
                value *= 10
                e += 1
            }
        } else {
            while e < exponent {
                value /= 10
                e += 1
            }
        }
    }

    var number = JsonValue:new_number()
    number.number = value * sign
    self.nodes += 1
    return number
}

// Forward declaration through a typed function value is unnecessary: RecurLoop
// resolves the phrase after the complete dictionary has been elaborated.
let Parser:parse_value = fn (self:Parser*) -> JsonValue* {
    Parser:skip_ws(self)

    if self.position >= self.length {
        self.errors += 1
        return cast(JsonValue*, 0)
    }

    var c = self.text[self.position]

    if c == 34 {
        var text = Parser:parse_string_text(self)
        if cast(i64, text) == 0 {
            return cast(JsonValue*, 0)
        }
        var value = JsonValue:new_string(text, Text:length(text))
        self.nodes += 1
        return value
    }

    if c == 123 {
        // object
        self.position += 1
        var object = JsonValue:new_container(5, 4)
        self.nodes += 1
        Parser:skip_ws(self)

        if self.position < self.length && self.text[self.position] == 125 {
            self.position += 1
            return object
        }

        var done = 0
        while done == 0 && self.position < self.length {
            var key = Parser:parse_string_text(self)
            if cast(i64, key) == 0 {
                done = 1
            } else if Parser:consume(self, 58) == 0 {
                free(key)
                done = 1
            } else {
                var child = Parser:parse_value(self)
                if cast(i64, child) == 0 {
                    free(key)
                    done = 1
                } else {
                    JsonValue:add_object(object, key, child)
                    Parser:skip_ws(self)

                    if self.position < self.length && self.text[self.position] == 44 {
                        self.position += 1
                        Parser:skip_ws(self)
                    } else if self.position < self.length && self.text[self.position] == 125 {
                        self.position += 1
                        done = 1
                    } else {
                        self.errors += 1
                        done = 1
                    }
                }
            }
        }

        return object
    }

    if c == 91 {
        // array
        self.position += 1
        var array = JsonValue:new_container(4, 4)
        self.nodes += 1
        Parser:skip_ws(self)

        if self.position < self.length && self.text[self.position] == 93 {
            self.position += 1
            return array
        }

        var done = 0
        while done == 0 && self.position < self.length {
            var child = Parser:parse_value(self)
            if cast(i64, child) == 0 {
                done = 1
            } else {
                JsonValue:add_array(array, child)
                Parser:skip_ws(self)

                if self.position < self.length && self.text[self.position] == 44 {
                    self.position += 1
                    Parser:skip_ws(self)
                } else if self.position < self.length && self.text[self.position] == 93 {
                    self.position += 1
                    done = 1
                } else {
                    self.errors += 1
                    done = 1
                }
            }
        }

        return array
    }

    if c == 116 {
        if Parser:match_literal(self, "true") != 0 {
            var value = JsonValue:new_bool(1)
            self.nodes += 1
            return value
        }
    }

    if c == 102 {
        if Parser:match_literal(self, "false") != 0 {
            var value = JsonValue:new_bool(0)
            self.nodes += 1
            return value
        }
    }

    if c == 110 {
        if Parser:match_literal(self, "null") != 0 {
            var value = JsonValue:new_null()
            self.nodes += 1
            return value
        }
    }

    if c == 45 || (c >= 48 && c <= 57) {
        return Parser:number(self)
    }

    self.errors += 1
    return cast(JsonValue*, 0)
}

let Parser:parse = fn (self:Parser*) -> JsonValue* {
    var root = Parser:parse_value(self)
    Parser:skip_ws(self)

    if self.position != self.length {
        self.errors += 1
    }

    return root
}


// ============================================================================
// Analytics
// ============================================================================

record Analytics {
    nodes:i64
    objects:i64
    arrays:i64
    strings:i64
    numbers:i64
    booleans:i64
    nulls:i64
    string_bytes:i64
    orders:i64
    items:i64
    active_customers:i64
    revenue:i64
    quantity:i64
    checksum:i64
}

let Analytics:new = fn () -> Analytics* {
    var stats:Analytics* = cast(Analytics*, malloc(112))
    stats.nodes = 0
    stats.objects = 0
    stats.arrays = 0
    stats.strings = 0
    stats.numbers = 0
    stats.booleans = 0
    stats.nulls = 0
    stats.string_bytes = 0
    stats.orders = 0
    stats.items = 0
    stats.active_customers = 0
    stats.revenue = 0
    stats.quantity = 0
    stats.checksum = 17
    return stats
}

let Analytics:destroy = fn (self:Analytics*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Analytics:mix = fn (self:Analytics*, value:i64) -> i64 {
    self.checksum = (self.checksum * 131 + value + 97) % 2147483647
    return 0
}

let JsonValue:walk = fn (self:JsonValue*, stats:Analytics*) -> i64 {
    stats.nodes += 1
    Analytics:mix(stats, self.kind * 17 + self.count)

    if self.kind == 0 {
        stats.nulls += 1
        return 0
    }

    if self.kind == 1 {
        stats.booleans += 1
        Analytics:mix(stats, self.boolean * 37)
        return 0
    }

    if self.kind == 2 {
        stats.numbers += 1
        Analytics:mix(stats, self.number)
        return 0
    }

    if self.kind == 3 {
        stats.strings += 1
        stats.string_bytes += self.text_length
        Analytics:mix(stats, Text:hash(self.text))
        return 0
    }

    if self.kind == 4 {
        stats.arrays += 1
        var i = 0
        while i < self.count {
            JsonValue:walk(cast(JsonValue*, self.children[i]), stats)
            i += 1
        }
        return 0
    }

    if self.kind == 5 {
        stats.objects += 1

        // Application-shaped object recognition. If an object looks like an
        // order line, aggregate price * quantity.
        var price = JsonValue:get(self, "price")
        var quantity = JsonValue:get(self, "quantity")
        if cast(i64, price) != 0 && cast(i64, quantity) != 0 {
            if price.kind == 2 && quantity.kind == 2 {
                stats.items += 1
                var item_quantity = quantity.number / 10000
                stats.quantity += item_quantity
                stats.revenue += price.number * item_quantity
            }
        }

        var order_id = JsonValue:get(self, "order_id")
        if cast(i64, order_id) != 0 {
            stats.orders += 1
        }

        var active = JsonValue:get(self, "active")
        var customer_id = JsonValue:get(self, "customer_id")
        if cast(i64, active) != 0 && cast(i64, customer_id) != 0 {
            if active.kind == 1 && active.boolean != 0 {
                stats.active_customers += 1
            }
        }

        var i = 0
        while i < self.count {
            Analytics:mix(stats, Text:hash(self.keys[i]))
            JsonValue:walk(cast(JsonValue*, self.children[i]), stats)
            i += 1
        }
    }

    return 0
}

// Apply a deterministic 3% price discount to every line item. This mutates the
// parsed tree and gives the benchmark a second traversal with writes.
let JsonValue:discount_prices = fn (self:JsonValue*) -> i64 {
    if self.kind == 5 {
        var i = 0
        while i < self.count {
            var child = cast(JsonValue*, self.children[i])
            if Text:equals(self.keys[i], "price") != 0 && child.kind == 2 {
                child.number = child.number * 97 / 100
            }
            JsonValue:discount_prices(child)
            i += 1
        }
        return 0
    }

    if self.kind == 4 {
        var i = 0
        while i < self.count {
            JsonValue:discount_prices(cast(JsonValue*, self.children[i]))
            i += 1
        }
    }

    return 0
}


// ============================================================================
// Benchmark result accumulator
// ============================================================================

record BenchmarkStats {
    iterations:i64
    parsed_nodes:i64
    parsed_strings:i64
    analytics_nodes:i64
    orders:i64
    items:i64
    quantity:i64
    active_customers:i64
    revenue:i64
    discounted_revenue:i64
    checksum:i64
}

let BenchmarkStats:new = fn () -> BenchmarkStats* {
    var stats:BenchmarkStats* = cast(BenchmarkStats*, malloc(88))
    stats.iterations = 0
    stats.parsed_nodes = 0
    stats.parsed_strings = 0
    stats.analytics_nodes = 0
    stats.orders = 0
    stats.items = 0
    stats.quantity = 0
    stats.active_customers = 0
    stats.revenue = 0
    stats.discounted_revenue = 0
    stats.checksum = 19
    return stats
}

let BenchmarkStats:destroy = fn (self:BenchmarkStats*) -> i64 {
    free(cast(u8*, self))
    return 0
}


// ============================================================================
// Realistic fixed input
// ============================================================================

let build_input_json = fn () -> u8* {
    var output:u8* = cast(u8*, malloc(4096))
    var offset = 0
    offset = Text:append(output, offset, "{\"generated_at\":\"2026-08-28T18:00:00Z\",\"source\":\"recurloop-commerce-demo\",\"version\":3,\"healthy\":")
    offset = Text:append(output, offset, "true,\"metadata\":{\"region\":\"eu-central\",\"currency\":\"PLN\",\"tags\":[\"benchmark\",\"commerce\",\"json\"],\"")
    offset = Text:append(output, offset, "nullable\":null},\"customers\":[{\"customer_id\":1001,\"name\":\"Anna Kowalska\",\"email\":\"anna@example.te")
    offset = Text:append(output, offset, "st\",\"active\":true,\"score\":91.75,\"address\":{\"city\":\"Poznan\",\"zip\":\"60-001\"}},{\"customer_id\":1002,")
    offset = Text:append(output, offset, "\"name\":\"Piotr Nowak\",\"email\":\"piotr@example.test\",\"active\":false,\"score\":72.5,\"address\":{\"city\":")
    offset = Text:append(output, offset, "\"Wroclaw\",\"zip\":\"50-001\"}},{\"customer_id\":1003,\"name\":\"Marta Zielinska\",\"email\":\"marta@example.t")
    offset = Text:append(output, offset, "est\",\"active\":true,\"score\":88.125,\"address\":{\"city\":\"Warsaw\",\"zip\":\"00-001\"}},{\"customer_id\":100")
    offset = Text:append(output, offset, "4,\"name\":\"Jan Wisniewski\",\"email\":\"jan@example.test\",\"active\":true,\"score\":95.0,\"address\":{\"city")
    offset = Text:append(output, offset, "\":\"Gdansk\",\"zip\":\"80-001\"}}],\"orders\":[{\"order_id\":50001,\"customer_id\":1001,\"status\":\"paid\",\"shi")
    offset = Text:append(output, offset, "pping\":18.99,\"items\":[{\"sku\":\"FRAME-A1\",\"name\":\"Steel frame\",\"price\":349.90,\"quantity\":2,\"tax\":0")
    offset = Text:append(output, offset, ".23},{\"sku\":\"LOCK-X2\",\"name\":\"Electronic lock\",\"price\":189.50,\"quantity\":2,\"tax\":0.23},{\"sku\":\"B")
    offset = Text:append(output, offset, "OLT-M12\",\"name\":\"Anchor bolt\",\"price\":14.25,\"quantity\":8,\"tax\":0.23}]},{\"order_id\":50002,\"custom")
    offset = Text:append(output, offset, "er_id\":1003,\"status\":\"processing\",\"shipping\":0.0,\"items\":[{\"sku\":\"RACK-8\",\"name\":\"Eight station ")
    offset = Text:append(output, offset, "rack\",\"price\":4299.00,\"quantity\":1,\"tax\":0.23},{\"sku\":\"CTRL-NFC\",\"name\":\"NFC controller\",\"price\"")
    offset = Text:append(output, offset, ":679.99,\"quantity\":1,\"tax\":0.23}]},{\"order_id\":50003,\"customer_id\":1004,\"status\":\"shipped\",\"ship")
    offset = Text:append(output, offset, "ping\":29.99,\"items\":[{\"sku\":\"ARM-SS\",\"name\":\"Stainless locking arm\",\"price\":259.40,\"quantity\":4,")
    offset = Text:append(output, offset, "\"tax\":0.23},{\"sku\":\"SENSOR-M\",\"name\":\"Motion sensor\",\"price\":84.75,\"quantity\":4,\"tax\":0.23},{\"sk")
    offset = Text:append(output, offset, "u\":\"BOX-IP65\",\"name\":\"IP65 electronics box\",\"price\":119.90,\"quantity\":2,\"tax\":0.23}]},{\"order_id")
    offset = Text:append(output, offset, "\":50004,\"customer_id\":1001,\"status\":\"paid\",\"shipping\":12.50,\"items\":[{\"sku\":\"GUIDE-W\",\"name\":\"Wh")
    offset = Text:append(output, offset, "eel guide\",\"price\":129.99,\"quantity\":3,\"tax\":0.23},{\"sku\":\"BEARING-T\",\"name\":\"Torque bearing\",\"p")
    offset = Text:append(output, offset, "rice\":74.60,\"quantity\":6,\"tax\":0.23}]},{\"order_id\":50005,\"customer_id\":1003,\"status\":\"cancelled\"")
    offset = Text:append(output, offset, ",\"shipping\":0.0,\"items\":[{\"sku\":\"PROTO-01\",\"name\":\"Prototype assembly\",\"price\":899.00,\"quantity\"")
    offset = Text:append(output, offset, ":1,\"tax\":0.23}]}],\"telemetry\":{\"parse_hint\":12345.6789,\"negative_test\":-42.125,\"scientific\":1.25")
    offset = Text:append(output, offset, "e3,\"escaped\":\"line one\nline two\ttabbed\",\"flags\":[true,false,true,true,false],\"matrix\":[[1,2,3]")
    offset = Text:append(output, offset, ",[4,5,6],[7,8,9]]}}")
    output[offset] = 0
    return output
}


// ============================================================================
// Self-test
// ============================================================================

let self_test = fn () -> i64 {
    var passed = 0
    var parser = Parser:new("{\"name\":\"recur\",\"n\":42.5,\"ok\":true,\"items\":[1,2,3],\"none\":null}")
    var root = Parser:parse(parser)

    if parser.errors == 0 {
        passed += 1
    }

    if cast(i64, root) != 0 && root.kind == 5 && root.count == 5 {
        passed += 1
    }

    var name = JsonValue:get(root, "name")
    if cast(i64, name) != 0 && name.kind == 3 && Text:equals(name.text, "recur") != 0 {
        passed += 1
    }

    var number = JsonValue:get(root, "n")
    if cast(i64, number) != 0 && number.kind == 2 {
        if number.number == 425000 {
            passed += 1
        }
    }

    var ok = JsonValue:get(root, "ok")
    if cast(i64, ok) != 0 && ok.kind == 1 && ok.boolean == 1 {
        passed += 1
    }

    var items = JsonValue:get(root, "items")
    if cast(i64, items) != 0 && items.kind == 4 && items.count == 3 {
        passed += 1
    }

    var none = JsonValue:get(root, "none")
    if cast(i64, none) != 0 && none.kind == 0 {
        passed += 1
    }

    JsonValue:destroy(root)
    Parser:destroy(parser)
    return passed
}


// ============================================================================
// Benchmark driver
// ============================================================================

let run_benchmark = fn (iterations:i64, result:BenchmarkStats*) -> i64 {
    var iteration = 0

    while iteration < iterations {
        var input = build_input_json()
        var parser = Parser:new(input)
        var root = Parser:parse(parser)

        if cast(i64, root) == 0 || parser.errors != 0 {
            if cast(i64, root) != 0 {
                JsonValue:destroy(root)
            }
            Parser:destroy(parser)
            free(input)
            return -1
        }

        var before = Analytics:new()
        JsonValue:walk(root, before)

        JsonValue:discount_prices(root)

        var after = Analytics:new()
        JsonValue:walk(root, after)

        result.iterations += 1
        result.parsed_nodes += parser.nodes
        result.parsed_strings += parser.strings
        result.analytics_nodes += before.nodes + after.nodes
        result.orders += before.orders
        result.items += before.items
        result.quantity += before.quantity
        result.active_customers += before.active_customers
        result.revenue += before.revenue
        result.discounted_revenue += after.revenue
        result.checksum *= 131
        result.checksum += before.checksum * 17
        result.checksum += after.checksum * 19
        result.checksum += parser.nodes * 23
        result.checksum += iteration
        result.checksum %= 2147483647

        Analytics:destroy(before)
        Analytics:destroy(after)
        JsonValue:destroy(root)
        Parser:destroy(parser)
        free(input)

        iteration += 1
    }

    return 0
}


// ============================================================================
// Report
// ============================================================================

let print_report = fn (result:BenchmarkStats*) -> i64 {
    printf("\n============================================================\n")
    printf(" RecurLoop JSON Parser + Analytics Benchmark\n")
    printf("============================================================\n")
    printf("iterations:          %lld\n", result.iterations)
    printf("parsed nodes:        %lld\n", result.parsed_nodes)
    printf("decoded strings:     %lld\n", result.parsed_strings)
    printf("analytics visits:    %lld\n", result.analytics_nodes)
    printf("\nCommerce aggregation\n")
    printf("--------------------\n")
    printf("orders observed:     %lld\n", result.orders)
    printf("line items:          %lld\n", result.items)
    printf("quantity:            %lld\n", result.quantity)
    printf("active customers:    %lld\n", result.active_customers)

    // Monetary totals use scale 10000. Divide by 100 to obtain cents.
    var revenue_cents = result.revenue / 100
    var discounted_cents = result.discounted_revenue / 100
    printf("revenue:             %lld.%02lld\n", revenue_cents / 100, revenue_cents % 100)
    printf("after 3%% discount:   %lld.%02lld\n", discounted_cents / 100, discounted_cents % 100)
    printf("checksum:            %lld\n", result.checksum)
    printf("============================================================\n")
    return 0
}


// ============================================================================
// Entry point
// ============================================================================

emit executable "/tmp/recurloop-json-processor" json_processor_main = fn (argc:i64, argv:u8**) -> i64 {
    var iterations = 2000

    if argc > 1 {
        iterations = Text:parse_i64(argv[1])
    }

    if iterations <= 0 {
        printf("error: iterations must be greater than zero\n")
        return 1
    }

    var test_score = self_test()
    if test_score != 7 {
        printf("self-test failed: %lld/7 checks passed\n", test_score)
        return 2
    }
    printf("self-test: 7/7 checks passed\n")

    var result = BenchmarkStats:new()
    defer BenchmarkStats:destroy(result)

    if run_benchmark(iterations, result) != 0 {
        printf("benchmark failed: JSON parser reported an error\n")
        return 3
    }

    print_report(result)
    printf("done\n")
    return 0
}

link clear

debug:stats
