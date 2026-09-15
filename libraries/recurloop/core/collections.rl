// Core compiler work-memory collections.
//
// These are ordinary RecurLoop records/functions persisted in core.rli. Live
// instances are process-local working memory and are never part of the semantic
// image. The only host boundary used here is raw byte allocation/copy/move.

let Core = []
let Core:Work = []

let Core:Work:next_capacity = fn (current:u64, minimum:u64) -> u64 {
    var capacity = current
    if capacity < 8 { capacity = 8 }
    while capacity < minimum {
        if capacity > 1152921504606846975 { return 0 }
        capacity *= 2
    }
    return capacity
}

record Core:Work:ByteBuffer {
    data:u8*
    length:u64
    capacity:u64
}

let Core:Work:ByteBuffer:new = fn (state:Context*, initial:u64) -> Core:Work:ByteBuffer* {
    let self = cast(Core:Work:ByteBuffer*, context:memory:allocate(state, 24))
    if !self { return cast(Core:Work:ByteBuffer*, 0) }
    self.data = cast(u8*, 0)
    self.length = 0
    self.capacity = 0
    if initial {
        let capacity = Core:Work:next_capacity(0, initial)
        self.data = context:memory:allocate(state, capacity)
        if !self.data { context:memory:release(state, cast(u8*, self)); return cast(Core:Work:ByteBuffer*, 0) }
        self.capacity = capacity
    }
    return self
}

let Core:Work:ByteBuffer:reserve = fn (self:Core:Work:ByteBuffer*, state:Context*, minimum:u64) -> i64 {
    if minimum <= self.capacity { return 1 }
    let capacity = Core:Work:next_capacity(self.capacity, minimum)
    if !capacity { return 0 }
    let replacement = context:memory:reallocate(state, self.data, capacity)
    if !replacement { return 0 }
    self.data = replacement
    self.capacity = capacity
    return 1
}

let Core:Work:ByteBuffer:push = fn (self:Core:Work:ByteBuffer*, state:Context*, value:u64) -> i64 {
    if self.length == self.capacity && !self.reserve(state, self.length + 1) { return 0 }
    self.data[self.length] = cast(u8, value)
    self.length += 1
    return 1
}

let Core:Work:ByteBuffer:append = fn (self:Core:Work:ByteBuffer*, state:Context*, source:u8*, bytes:u64) -> i64 {
    if !bytes { return 1 }
    if !source { return 0 }
    let old = self.length
    if !self.reserve(state, old + bytes) { return 0 }
    context:memory:move(state, &self.data[old], source, bytes)
    self.length = old + bytes
    return 1
}

let Core:Work:ByteBuffer:clear = fn (self:Core:Work:ByteBuffer*) -> void { self.length = 0 }

let Core:Work:ByteBuffer:destroy = fn (self:Core:Work:ByteBuffer*, state:Context*) -> void {
    if !self { return }
    if self.data { context:memory:release(state, self.data) }
    context:memory:release(state, cast(u8*, self))
}

record Core:Work:U64Vector {
    data:u64*
    length:u64
    capacity:u64
}

let Core:Work:U64Vector:new = fn (state:Context*, initial:u64) -> Core:Work:U64Vector* {
    let self = cast(Core:Work:U64Vector*, context:memory:allocate(state, 24))
    if !self { return cast(Core:Work:U64Vector*, 0) }
    self.data = cast(u64*, 0)
    self.length = 0
    self.capacity = 0
    if initial {
        let capacity = Core:Work:next_capacity(0, initial)
        self.data = cast(u64*, context:memory:allocate(state, capacity * 8))
        if !self.data { context:memory:release(state, cast(u8*, self)); return cast(Core:Work:U64Vector*, 0) }
        self.capacity = capacity
    }
    return self
}

let Core:Work:U64Vector:reserve = fn (self:Core:Work:U64Vector*, state:Context*, minimum:u64) -> i64 {
    if minimum <= self.capacity { return 1 }
    let capacity = Core:Work:next_capacity(self.capacity, minimum)
    if !capacity { return 0 }
    let replacement = context:memory:reallocate(state, cast(u8*, self.data), capacity * 8)
    if !replacement { return 0 }
    self.data = cast(u64*, replacement)
    self.capacity = capacity
    return 1
}

let Core:Work:U64Vector:push = fn (self:Core:Work:U64Vector*, state:Context*, value:u64) -> i64 {
    if self.length == self.capacity && !self.reserve(state, self.length + 1) { return 0 }
    self.data[self.length] = value
    self.length += 1
    return 1
}

let Core:Work:U64Vector:pop = fn (self:Core:Work:U64Vector*, output:u64*) -> i64 {
    if !self.length { return 0 }
    self.length -= 1
    if output { output[0] = self.data[self.length] }
    return 1
}

let Core:Work:U64Vector:get = fn (self:Core:Work:U64Vector*, index:u64, output:u64*) -> i64 {
    if index >= self.length || !output { return 0 }
    output[0] = self.data[index]
    return 1
}

let Core:Work:U64Vector:set = fn (self:Core:Work:U64Vector*, index:u64, value:u64) -> i64 {
    if index >= self.length { return 0 }
    self.data[index] = value
    return 1
}

let Core:Work:U64Vector:clear = fn (self:Core:Work:U64Vector*) -> void { self.length = 0 }

let Core:Work:U64Vector:destroy = fn (self:Core:Work:U64Vector*, state:Context*) -> void {
    if !self { return }
    if self.data { context:memory:release(state, cast(u8*, self.data)) }
    context:memory:release(state, cast(u8*, self))
}

record Core:Work:U64Deque {
    data:u64*
    head:u64
    length:u64
    capacity:u64
}

let Core:Work:U64Deque:new = fn (state:Context*, initial:u64) -> Core:Work:U64Deque* {
    let self = cast(Core:Work:U64Deque*, context:memory:allocate(state, 32))
    if !self { return cast(Core:Work:U64Deque*, 0) }
    self.data = cast(u64*, 0)
    self.head = 0
    self.length = 0
    self.capacity = 0
    if initial {
        let capacity = Core:Work:next_capacity(0, initial)
        self.data = cast(u64*, context:memory:allocate(state, capacity * 8))
        if !self.data { context:memory:release(state, cast(u8*, self)); return cast(Core:Work:U64Deque*, 0) }
        self.capacity = capacity
    }
    return self
}

let Core:Work:U64Deque:reserve = fn (self:Core:Work:U64Deque*, state:Context*, minimum:u64) -> i64 {
    if minimum <= self.capacity { return 1 }
    let capacity = Core:Work:next_capacity(self.capacity, minimum)
    if !capacity { return 0 }
    let replacement = cast(u64*, context:memory:allocate(state, capacity * 8))
    if !replacement { return 0 }
    var index = 0
    while index < self.length {
        if self.capacity { replacement[index] = self.data[(self.head + index) % self.capacity] }
        index += 1
    }
    if self.data { context:memory:release(state, cast(u8*, self.data)) }
    self.data = replacement
    self.head = 0
    self.capacity = capacity
    return 1
}

let Core:Work:U64Deque:push_back = fn (self:Core:Work:U64Deque*, state:Context*, value:u64) -> i64 {
    if self.length == self.capacity && !self.reserve(state, self.length + 1) { return 0 }
    self.data[(self.head + self.length) % self.capacity] = value
    self.length += 1
    return 1
}

let Core:Work:U64Deque:push_front = fn (self:Core:Work:U64Deque*, state:Context*, value:u64) -> i64 {
    if self.length == self.capacity && !self.reserve(state, self.length + 1) { return 0 }
    if self.head == 0 { self.head = self.capacity - 1 } else { self.head -= 1 }
    self.data[self.head] = value
    self.length += 1
    return 1
}

let Core:Work:U64Deque:pop_front = fn (self:Core:Work:U64Deque*, output:u64*) -> i64 {
    if !self.length { return 0 }
    if output { output[0] = self.data[self.head] }
    self.head = (self.head + 1) % self.capacity
    self.length -= 1
    if !self.length { self.head = 0 }
    return 1
}

let Core:Work:U64Deque:pop_back = fn (self:Core:Work:U64Deque*, output:u64*) -> i64 {
    if !self.length { return 0 }
    let index = (self.head + self.length - 1) % self.capacity
    if output { output[0] = self.data[index] }
    self.length -= 1
    if !self.length { self.head = 0 }
    return 1
}

let Core:Work:U64Deque:at = fn (self:Core:Work:U64Deque*, index:u64, output:u64*) -> i64 {
    if index >= self.length || !output { return 0 }
    output[0] = self.data[(self.head + index) % self.capacity]
    return 1
}

let Core:Work:U64Deque:destroy = fn (self:Core:Work:U64Deque*, state:Context*) -> void {
    if !self { return }
    if self.data { context:memory:release(state, cast(u8*, self.data)) }
    context:memory:release(state, cast(u8*, self))
}

record Core:Work:U64MapEntry { key:u64 value:u64 state:u64 }
record Core:Work:U64Map { entries:Core:Work:U64MapEntry* length:u64 capacity:u64 tombstones:u64 }

let Core:Work:hash_u64 = fn (value:u64) -> u64 {
    var x = value % 2147483647
    x = (x * 131 + 17) % 2147483647
    x = (x * 131 + 97) % 2147483647
    return x
}

let Core:Work:U64Map:new = fn (state:Context*, initial:u64) -> Core:Work:U64Map* {
    let self = cast(Core:Work:U64Map*, context:memory:allocate(state, 32))
    if !self { return cast(Core:Work:U64Map*, 0) }
    var capacity = Core:Work:next_capacity(0, initial)
    self.entries = cast(Core:Work:U64MapEntry*, context:memory:allocate(state, capacity * 24))
    if !self.entries { context:memory:release(state, cast(u8*, self)); return cast(Core:Work:U64Map*, 0) }
    var index = 0
    while index < capacity { self.entries[index].state = 0; index += 1 }
    self.length = 0
    self.capacity = capacity
    self.tombstones = 0
    return self
}

let Core:Work:U64Map:insert_raw = fn (self:Core:Work:U64Map*, key:u64, value:u64) -> i64 {
    var slot = Core:Work:hash_u64(key) % self.capacity
    var tombstone = self.capacity
    var probes = 0
    while probes < self.capacity {
        let marker = self.entries[slot].state
        if marker == 0 {
            var destination = slot
            if tombstone < self.capacity { destination = tombstone; self.tombstones -= 1 }
            self.entries[destination].key = key
            self.entries[destination].value = value
            self.entries[destination].state = 1
            self.length += 1
            return 1
        }
        if marker == 1 && self.entries[slot].key == key { self.entries[slot].value = value; return 1 }
        if marker == 2 && tombstone == self.capacity { tombstone = slot }
        slot = (slot + 1) % self.capacity
        probes += 1
    }
    return 0
}

let Core:Work:U64Map:rehash = fn (self:Core:Work:U64Map*, state:Context*, requested:u64) -> i64 {
    let capacity = Core:Work:next_capacity(0, requested)
    let replacement = cast(Core:Work:U64MapEntry*, context:memory:allocate(state, capacity * 24))
    if !replacement { return 0 }
    var index = 0
    while index < capacity { replacement[index].state = 0; index += 1 }
    let old = self.entries
    let old_capacity = self.capacity
    self.entries = replacement
    self.capacity = capacity
    self.length = 0
    self.tombstones = 0
    index = 0
    while index < old_capacity {
        if old[index].state == 1 { if !self.insert_raw(old[index].key, old[index].value) { context:memory:release(state, cast(u8*, old)); return 0 } }
        index += 1
    }
    context:memory:release(state, cast(u8*, old))
    return 1
}

let Core:Work:U64Map:put = fn (self:Core:Work:U64Map*, state:Context*, key:u64, value:u64) -> i64 {
    if (self.length + self.tombstones + 1) * 10 >= self.capacity * 7 {
        if !self.rehash(state, self.capacity * 2) { return 0 }
    }
    return self.insert_raw(key, value)
}

let Core:Work:U64Map:get = fn (self:Core:Work:U64Map*, key:u64, output:u64*) -> i64 {
    var slot = Core:Work:hash_u64(key) % self.capacity
    var probes = 0
    while probes < self.capacity {
        let marker = self.entries[slot].state
        if marker == 0 { return 0 }
        if marker == 1 && self.entries[slot].key == key { if output { output[0] = self.entries[slot].value }; return 1 }
        slot = (slot + 1) % self.capacity
        probes += 1
    }
    return 0
}

let Core:Work:U64Map:remove = fn (self:Core:Work:U64Map*, key:u64, output:u64*) -> i64 {
    var slot = Core:Work:hash_u64(key) % self.capacity
    var probes = 0
    while probes < self.capacity {
        let marker = self.entries[slot].state
        if marker == 0 { return 0 }
        if marker == 1 && self.entries[slot].key == key {
            if output { output[0] = self.entries[slot].value }
            self.entries[slot].state = 2
            self.length -= 1
            self.tombstones += 1
            return 1
        }
        slot = (slot + 1) % self.capacity
        probes += 1
    }
    return 0
}

let Core:Work:U64Map:destroy = fn (self:Core:Work:U64Map*, state:Context*) -> void {
    if !self { return }
    if self.entries { context:memory:release(state, cast(u8*, self.entries)) }
    context:memory:release(state, cast(u8*, self))
}

record Core:Work:ArenaBlock { next:Core:Work:ArenaBlock* data:u8* used:u64 capacity:u64 }
record Core:Work:Arena { head:Core:Work:ArenaBlock* default_capacity:u64 }

let Core:Work:Arena:new = fn (state:Context*, default_capacity:u64) -> Core:Work:Arena* {
    let self = cast(Core:Work:Arena*, context:memory:allocate(state, 16))
    if !self { return cast(Core:Work:Arena*, 0) }
    self.head = cast(Core:Work:ArenaBlock*, 0)
    if default_capacity < 256 { default_capacity = 256 }
    self.default_capacity = default_capacity
    return self
}

let Core:Work:Arena:add_block = fn (self:Core:Work:Arena*, state:Context*, minimum:u64) -> i64 {
    var capacity = self.default_capacity
    if capacity < minimum { capacity = minimum }
    let block = cast(Core:Work:ArenaBlock*, context:memory:allocate(state, 32))
    if !block { return 0 }
    block.data = context:memory:allocate(state, capacity)
    if !block.data { context:memory:release(state, cast(u8*, block)); return 0 }
    block.next = self.head
    block.used = 0
    block.capacity = capacity
    self.head = block
    return 1
}

let Core:Work:Arena:alloc_aligned = fn (self:Core:Work:Arena*, state:Context*, bytes:u64, alignment:u64) -> u8* {
    if !bytes { return cast(u8*, 0) }
    if alignment == 0 { alignment = 1 }
    if alignment != 1 && alignment != 2 && alignment != 4 && alignment != 8 { return cast(u8*, 0) }
    if !self.head && !self.add_block(state, bytes + alignment) { return cast(u8*, 0) }
    var offset = ((self.head.used + alignment - 1) / alignment) * alignment
    if offset + bytes > self.head.capacity {
        if !self.add_block(state, bytes + alignment) { return cast(u8*, 0) }
        offset = 0
    }
    let result = &self.head.data[offset]
    self.head.used = offset + bytes
    return result
}

let Core:Work:Arena:alloc = fn (self:Core:Work:Arena*, state:Context*, bytes:u64) -> u8* {
    return self.alloc_aligned(state, bytes, 8)
}

let Core:Work:Arena:destroy = fn (self:Core:Work:Arena*, state:Context*) -> void {
    if !self { return }
    var block = self.head
    while block {
        let next = block.next
        context:memory:release(state, block.data)
        context:memory:release(state, cast(u8*, block))
        block = next
    }
    context:memory:release(state, cast(u8*, self))
}

// Executed by the feature test, not during every core build.
let Core:Work:selftest = fn (state:Context*) -> i64 {
    let vector = Core:Work:U64Vector:new(state, 0)
    let deque = Core:Work:U64Deque:new(state, 0)
    let map = Core:Work:U64Map:new(state, 4)
    let arena = Core:Work:Arena:new(state, 64)
    if !vector || !deque || !map || !arena { return 0 }
    defer vector.destroy(state)
    defer deque.destroy(state)
    defer map.destroy(state)
    defer arena.destroy(state)

    if !vector.push(state, 10) || !vector.push(state, 20) { return 0 }
    var value:u64 = 0
    if !vector.get(1, &value) || value != 20 { return 0 }
    if !deque.push_back(state, 2) || !deque.push_front(state, 1) || !deque.push_back(state, 3) { return 0 }
    if !deque.pop_front(&value) || value != 1 { return 0 }
    if !map.put(state, 7, 70) || !map.put(state, 8, 80) { return 0 }
    if !map.get(8, &value) || value != 80 { return 0 }
    if !arena.alloc_aligned(state, 17, 8) { return 0 }
    return 1
}

let Core:Work:SelfTest = phrase {
    type = <phrase-types:callable>
    action = fn (state:Context*, called:Phrase*) -> void {
        if !Core:Work:selftest(state) {
            context:diagnostic:error(state, "core compiler work-memory self-test failed")
            return
        }
        context:source:root(state)
        return
    }
}
