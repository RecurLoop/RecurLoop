// ============================================================================
// RecurLoop Showcase — Priority Task Queue
//
// Demonstrates the modern features of RecurLoop:
//   - Namespaces as dictionaries with nested entries
//   - Records with typed fields and pointer members
//   - Native typed functions with explicit ABI conventions
//   - One compiled `fn` model for runtime calls and emitted binaries
//   - Methods on records (first param = receiver pointer)
//   - Defer for LIFO cleanup with proper ordering
//   - Null pointer propagation with ?
//   - Module management: auto, clear, strip, entry
//   - Linking: shared libraries, clear
//   - Extern declarations with ABI
//   - Const-time evaluation and assert
//   - String operations: str(), +, contains()
//   - Emit executable with argv entry point
//   - Pointer casting and raw memory via malloc/free
// ============================================================================

// ---------------------------------------------------------------------------
// Shared C library for memory management and I/O
// ---------------------------------------------------------------------------

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(ptr:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64

// ---------------------------------------------------------------------------
// I/O helpers — a small namespace wrapping printf
// ---------------------------------------------------------------------------

let IO = [
    ln = fn () -> i64 {
        return printf("\n")
    }

    s = fn (text:u8*) -> i64 {
        return printf("%s", text)
    }

    i = fn (value:i64) -> i64 {
        return printf("%lld", value)
    }

    ic = fn (value:i64) -> i64 {
        return printf("%lld:", value)
    }

    ip = fn (value:i64) -> i64 {
        return printf("%lld ", value)
    }

    t = fn (text:u8*) -> i64 {
        return printf("    %s\n", text)
    }
]

// ---------------------------------------------------------------------------
// Core data types — records
// ---------------------------------------------------------------------------

record Task {
    id:i64
    priority:i64
    name:u8*
}

record TaskQueue {
    capacity:i64
    count:i64
    tasks:Task**
}

// ---------------------------------------------------------------------------
// Task — constructor and destructor as methods
// ---------------------------------------------------------------------------

let Task:new = fn (tid:i64, priority:i64, name:u8*) -> Task* {
    var t:Task* = cast(Task*, malloc(24))
    t.id = tid
    t.priority = priority
    t.name = name
    return t
}

let Task:destroy = fn (self:Task*) -> i64 {
    free(cast(u8*, self))
    return 0
}

let Task:label = fn (self:Task*) -> u8* {
    return self.name
}

// ---------------------------------------------------------------------------
// TaskQueue — full CRUD + algorithms
// ---------------------------------------------------------------------------

let TaskQueue:new = fn (capacity:i64) -> TaskQueue* {
    var q:TaskQueue* = cast(TaskQueue*, malloc(24))
    q.capacity = capacity
    q.count = 0
    q.tasks = cast(Task**, malloc(capacity * 8))
    return q
}

let TaskQueue:destroy = fn (self:TaskQueue*) -> i64 {
    var i = 0
    while i < self.count {
        Task:destroy(self.tasks[i])
        i += 1
    }
    free(cast(u8*, self.tasks))
    free(cast(u8*, self))
    return 0
}

let TaskQueue:is_full = fn (self:TaskQueue*) -> i64 {
    return self.count >= self.capacity
}

let TaskQueue:insert = fn (self:TaskQueue*, task:Task*) -> i64 {
    if TaskQueue:is_full(self) {
        return -1
    }
    self.tasks[self.count] = task
    self.count += 1
    return 0
}

let TaskQueue:remove = fn (self:TaskQueue*, rid:i64) -> Task* {
    var i = 0
    while i < self.count {
        if self.tasks[i].id == rid {
            var removed = self.tasks[i]
            var j = i + 1
            while j < self.count {
                self.tasks[j - 1] = self.tasks[j]
                j += 1
            }
            self.count -= 1
            return removed
        }
        i += 1
    }
    return cast(Task*, 0)
}

let TaskQueue:find = fn (self:TaskQueue*, rid:i64) -> Task* {
    var i = 0
    while i < self.count {
        if self.tasks[i].id == rid {
            return self.tasks[i]
        }
        i += 1
    }
    return cast(Task*, 0)
}

// ---------------------------------------------------------------------------
// TaskQueue algorithms — bubble sort, stats
// ---------------------------------------------------------------------------

let TaskQueue:sort = fn (self:TaskQueue*) -> i64 {
    var i = 0
    while i < self.count - 1 {
        var j = 0
        while j < self.count - i - 1 {
            if self.tasks[j].priority < self.tasks[j + 1].priority {
                var tmp = self.tasks[j]
                self.tasks[j] = self.tasks[j + 1]
                self.tasks[j + 1] = tmp
            }
            j += 1
        }
        i += 1
    }
    return 0
}

let TaskQueue:top = fn (self:TaskQueue*) -> Task* {
    if self.count == 0 {
        return cast(Task*, 0)
    }
    return self.tasks[0]
}

let TaskQueue:priority_sum = fn (self:TaskQueue*) -> i64 {
    var sum = 0
    var i = 0
    while i < self.count {
        sum += self.tasks[i].priority
        i += 1
    }
    return sum
}

let TaskQueue:priority_avg = fn (self:TaskQueue*) -> i64 {
    if self.count == 0 {
        return 0
    }
    return TaskQueue:priority_sum(self) / self.count
}

let TaskQueue:max_priority = fn (self:TaskQueue*) -> i64 {
    if self.count == 0 {
        return 0
    }
    var max = self.tasks[0].priority
    var i = 1
    while i < self.count {
        if self.tasks[i].priority > max {
            max = self.tasks[i].priority
        }
        i += 1
    }
    return max
}

let TaskQueue:min_priority = fn (self:TaskQueue*) -> i64 {
    if self.count == 0 {
        return 0
    }
    var min = self.tasks[0].priority
    var i = 1
    while i < self.count {
        if self.tasks[i].priority < min {
            min = self.tasks[i].priority
        }
        i += 1
    }
    return min
}

// ---------------------------------------------------------------------------
// TaskQueue display — formatted output
// ---------------------------------------------------------------------------

let TaskQueue:display = fn (self:TaskQueue*) -> i64 {
    printf("  queue: %lld/%lld\n", self.count, self.capacity)
    printf("  avg priority: %lld\n", TaskQueue:priority_avg(self))

    if self.count == 0 {
        printf("  (empty)\n")
        return 0
    }

    printf("  sorted by priority:\n")
    TaskQueue:sort(self)

    var i = 0
    while i < self.count {
        printf("    #%lld: priority=%lld %s\n", self.tasks[i].id, self.tasks[i].priority, self.tasks[i].name)
        i += 1
    }
    return 0
}

let TaskQueue:stats = fn (self:TaskQueue*) -> i64 {
    printf("  tasks: %lld/%lld\n", self.count, self.capacity)
    printf("  priority sum: %lld\n", TaskQueue:priority_sum(self))
    printf("  priority avg: %lld\n", TaskQueue:priority_avg(self))
    printf("  priority max: %lld\n", TaskQueue:max_priority(self))
    printf("  priority min: %lld\n", TaskQueue:min_priority(self))
    return 0
}

// ---------------------------------------------------------------------------
// Compiled functions — the direct and `let` forms share one implementation.
// ---------------------------------------------------------------------------

fn fib(n:i64) -> i64 {
    if n <= 1 {
        return n
    }
    return fib(n - 1) + fib(n - 2)
}

const fn_fib = fib(10)
assert fn_fib == 55
print "showcase: compiled fib(10) = " + str(fn_fib)

// ---------------------------------------------------------------------------
// Null-safety — ? propagates null from pointer-returning functions
// ---------------------------------------------------------------------------

let Safety = [
    check = fn (ptr:Task*) -> Task* {
        return ptr?
    }
]

// ---------------------------------------------------------------------------
// Compile-time assertions
// ---------------------------------------------------------------------------

const task_size = 24
const queue_size = 24
assert task_size > 0
assert queue_size > 0

// ---------------------------------------------------------------------------
// Self-test — runs at runtime inside the executable
// ---------------------------------------------------------------------------

let self_test = fn () -> i64 {
    var q = TaskQueue:new(4)
    defer TaskQueue:destroy(q)

    var t1 = Task:new(1, 10, "alpha")
    var t2 = Task:new(2, 30, "beta")
    var t3 = Task:new(3, 5, "gamma")

    TaskQueue:insert(q, t1)
    TaskQueue:insert(q, t2)
    TaskQueue:insert(q, t3)

    var score = 0

    if q.count == 3 {
        score += 1
    }

    if TaskQueue:priority_sum(q) == 45 {
        score += 1
    }

    if TaskQueue:priority_avg(q) == 15 {
        score += 1
    }

    if TaskQueue:max_priority(q) == 30 {
        score += 1
    }

    if TaskQueue:min_priority(q) == 5 {
        score += 1
    }

    TaskQueue:sort(q)

    if q.tasks[0].priority == 30 {
        score += 1
    }

    if q.tasks[1].priority == 10 {
        score += 1
    }

    if q.tasks[2].priority == 5 {
        score += 1
    }

    var removed = TaskQueue:remove(q, 2)
    if removed != cast(Task*, 0) && removed.id == 2 {
        score += 1
    }

    if q.count == 2 {
        score += 1
    }

    var missing = TaskQueue:find(q, 99)
    if missing == cast(Task*, 0) {
        score += 1
    }

    var safe = Safety:check(cast(Task*, 0))
    if safe == cast(Task*, 0) {
        score += 1
    }

    Task:destroy(removed)
    // q and remaining tasks freed by deferred TaskQueue:destroy
    return score
}

// Standalone executable — self-test + CLI demo
// ---------------------------------------------------------------------------

module auto
module clear
module strip
module entry showcase_main

emit executable "/tmp/recurloop-showcase" showcase_main = fn (argc:i64, argv:u8**) -> i64 {
    printf("RecurLoop Priority Task Queue\n")
    printf("=============================\n\n")

    var score = self_test()
    printf("self-test: %lld/12 checks passed\n\n", score)

    if argc < 2 {
        printf("usage: %s <add ID PRI NAME> [remove ID] [list] [top] [stats]\n", argv[0])
        printf("\nexample:\n")
        printf("  %s add 1 10 deploy add 2 50 backup list top stats\n", argv[0])
        return 1
    }

    var q = TaskQueue:new(100)
    defer TaskQueue:destroy(q)

    var cmd:u8* = argv[0]
    var arg_i = 1
    var ci = 0

    while arg_i < argc {
        cmd = cast(u8*, argv[arg_i])

        if cmd[0]==97 && cmd[1]==100 && cmd[2]==100 && arg_i + 3 < argc {
            var add_id = 0
            var p1:u8* = argv[arg_i + 1]
            ci = 0
            while p1[ci] >= 48 && p1[ci] <= 57 {
                add_id = add_id * 10 + p1[ci] - 48
                ci += 1
            }

            var pri = 0
            var p2:u8* = argv[arg_i + 2]
            ci = 0
            while p2[ci] >= 48 && p2[ci] <= 57 {
                pri = pri * 10 + p2[ci] - 48
                ci += 1
            }

            var name:u8* = argv[arg_i + 3]
            var task = Task:new(add_id, pri, name)

            if TaskQueue:insert(q, task) == 0 {
                printf("  added: %s (id=%lld p=%lld)\n", name, add_id, pri)
            } else {
                printf("  queue full\n")
                Task:destroy(task)
            }
            arg_i += 4
        } else if cmd[0]==114 && cmd[1]==101 && cmd[2]==109 && cmd[3]==111 && cmd[4]==118 && cmd[5]==101 && arg_i + 1 < argc {
            var rm_id = 0
            var pr:u8* = argv[arg_i + 1]
            ci = 0
            while pr[ci] >= 48 && pr[ci] <= 57 {
                rm_id = rm_id * 10 + pr[ci] - 48
                ci += 1
            }

            var removed = TaskQueue:remove(q, rm_id)
            if removed != cast(Task*, 0) {
                printf("  removed: %s (id=%lld)\n", removed.name, rm_id)
                Task:destroy(removed)
            } else {
                printf("  not found: id=%lld\n", rm_id)
            }
            arg_i += 2
        } else if cmd[0]==108 && cmd[1]==105 && cmd[2]==115 && cmd[3]==116 {
            TaskQueue:display(q)
            arg_i += 1
        } else if cmd[0]==116 && cmd[1]==111 && cmd[2]==112 {
            TaskQueue:sort(q)
            var t = TaskQueue:top(q)
            if t != cast(Task*, 0) {
                printf("  top: %s (id=%lld p=%lld)\n", t.name, t.id, t.priority)
            } else {
                printf("  (queue empty)\n")
            }
            arg_i += 1
        } else if cmd[0]==115 && cmd[1]==116 && cmd[2]==97 && cmd[3]==116 && cmd[4]==115 {
            TaskQueue:stats(q)
            arg_i += 1
        } else {
            printf("  unknown command: %s\n", cmd)
            arg_i += 1
        }
    }

    printf("=============================\n")
    printf("done\n")
    return 0
}

link clear

debug:stats
