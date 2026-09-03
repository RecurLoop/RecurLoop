// ============================================================================
// RecurLoop production containers example
//
// This example intentionally mixes two layers:
//   1. a source-defined `vector` declaration implemented as an .rl phrase;
//   2. production-shaped runtime containers built on top of the generated
//      vector types.
//
// The `vector Name ElementType {}` phrase creates both a namespace and a real
// structure type during elaboration. Later functions compile against that
// generated type exactly as if it had been declared with `record`.
//
// Build:
//   make example EXAMPLE=05-applications/containers BUILD_TYPE=Release
//
// Run:
//   /tmp/recurloop-containers-production
// ============================================================================

link shared "c"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
extern printf(format:u8*, ...) -> i64 abi sysv-amd64
extern memmove(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64
extern memcpy(destination:u8*, source:u8*, bytes:u64) -> u8* abi sysv-amd64

let Containers = []
let Containers:Meta = []

// ============================================================================
// Compile-time vector type factory.
// ============================================================================

let Containers:Meta:is_space = fn (value:i64) -> i64 {
    return value == 32 || value == 9 || value == 10 || value == 13
}

let vector = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let block = context:source:block:capture(state)
        if !block {
            return
        }
        defer context:source:block:release(block)

        let header = context:source:block:header(block)
        var index = 0

        while Containers:Meta:is_space(header[index]) {
            index += 1
        }

        let name_start = index
        while header[index] != 0 && !Containers:Meta:is_space(header[index]) {
            index += 1
        }
        let name_length = index - name_start
        if name_length <= 0 {
            context:diagnostic:error(state, "vector expects: vector Name ElementType { }")
            return
        }

        while Containers:Meta:is_space(header[index]) {
            index += 1
        }

        let type_start = index
        while header[index] != 0 && !Containers:Meta:is_space(header[index]) {
            index += 1
        }
        var type_length = index - type_start
        if type_length <= 0 {
            context:diagnostic:error(state, "vector expects an element type")
            return
        }

        while Containers:Meta:is_space(header[index]) {
            index += 1
        }
        if header[index] != 0 {
            context:diagnostic:error(state, "vector accepts exactly a name and one element type")
            return
        }

        let name = malloc(name_length + 1)
        if !name {
            context:diagnostic:error(state, "out of memory while declaring vector type")
            return
        }
        defer free(name)

        var copied = 0
        while copied < name_length {
            name[copied] = header[name_start + copied]
            copied += 1
        }
        name[name_length] = 0

        // Pointer element types are accepted as a suffix (`Foo*`, `i64**`, ...)
        // and are composed using the public Context type API.
        var pointer_depth = 0
        while type_length > 0 && header[type_start + type_length - 1] == 42 {
            pointer_depth += 1
            type_length -= 1
        }
        if type_length <= 0 {
            context:diagnostic:error(state, "vector element type cannot consist only of pointers")
            return
        }

        let element_name = malloc(type_length + 1)
        if !element_name {
            context:diagnostic:error(state, "out of memory while resolving vector element type")
            return
        }
        defer free(element_name)

        copied = 0
        while copied < type_length {
            element_name[copied] = header[type_start + copied]
            copied += 1
        }
        element_name[type_length] = 0

        var element_type = context:type:find(state, element_name)
        if element_type == 0 {
            context:diagnostic:error(state, "vector element type is not defined")
            return
        }
        while pointer_depth > 0 {
            element_type = context:type:pointer(state, element_type)
            pointer_depth -= 1
        }

        if context:type:find(state, name) != 0 {
            context:diagnostic:error(state, "vector type name is already defined")
            return
        }

        // The dictionary is the public namespace used later for methods such as
        // I64Vector:push. It is created by the library, not written by the user.
        if context:phrase:find(state, name) == 0 {
            context:phrase:define:dictionary(state, name)
        }

        // Structure fields need a phrase chain. Keep it in a private generated
        // dictionary so field descriptors do not pollute the public namespace.
        let prefix = "__recurloop_vector_fields_"
        var prefix_length = 0
        while prefix[prefix_length] != 0 {
            prefix_length += 1
        }

        let owner_name = malloc(prefix_length + name_length + 1)
        if !owner_name {
            context:diagnostic:error(state, "out of memory while declaring vector fields")
            return
        }
        defer free(owner_name)

        copied = 0
        while copied < prefix_length {
            owner_name[copied] = prefix[copied]
            copied += 1
        }
        var name_index = 0
        while name_index < name_length {
            owner_name[prefix_length + name_index] = name[name_index]
            name_index += 1
        }
        owner_name[prefix_length + name_length] = 0

        let field_owner = context:phrase:define:dictionary(state, owner_name)
        if field_owner == 0 {
            context:diagnostic:error(state, "could not create vector field dictionary")
            return
        }

        let i64_type = context:type:find(state, "i64")
        let data_type = context:type:pointer(state, element_type)

        let capacity_field = context:phrase:define:data(state, field_owner, "capacity")
        context:phrase:data(state, capacity_field, &i64_type, 0, 8)

        let length_field = context:phrase:define:successor(state, field_owner, "length", capacity_field)
        context:phrase:data(state, length_field, &i64_type, 0, 8)

        let data_field = context:phrase:define:successor(state, field_owner, "data", length_field)
        context:phrase:data(state, data_field, &data_type, 0, 8)

        let structure = context:type:structure:declare(state, name)
        if structure == 0 {
            context:diagnostic:error(state, "could not declare vector structure")
            return
        }
        context:type:structure:complete:natural(state, structure, data_field)

        if context:type:size(state, structure) != 24 || context:type:alignment(state, structure) != 8 {
            context:diagnostic:error(state, "generated vector layout is invalid")
        }
    }
}

// Two concrete types are monomorphized by the same library phrase.
vector I64Vector i64 {
}

vector ByteVector u8 {
}

// ============================================================================
// Shared vector helpers.
// ============================================================================

let Containers:next_capacity = fn (current:i64, minimum:i64) -> i64 {
    var capacity = current
    if capacity < 8 {
        capacity = 8
    }

    while capacity < minimum {
        if capacity > 576460752303423487 {
            return 0
        }
        capacity *= 2
    }
    return capacity
}

// ============================================================================
// I64Vector - generated structure, production-shaped API.
// ============================================================================

let I64Vector:new = fn (initial_capacity:i64) -> I64Vector* {
    let self = cast(I64Vector*, malloc(24))
    if !self {
        return cast(I64Vector*, 0)
    }

    self.data = cast(i64*, 0)
    self.length = 0
    self.capacity = 0

    if initial_capacity > 0 {
        let capacity = Containers:next_capacity(0, initial_capacity)
        if capacity == 0 {
            free(cast(u8*, self))
            return cast(I64Vector*, 0)
        }
        self.data = cast(i64*, malloc(capacity * 8))
        if !self.data {
            free(cast(u8*, self))
            return cast(I64Vector*, 0)
        }
        self.capacity = capacity
    }
    return self
}

let I64Vector:reserve = fn (self:I64Vector*, minimum:i64) -> i64 {
    if minimum <= self.capacity {
        return 1
    }
    if minimum < 0 {
        return 0
    }

    let capacity = Containers:next_capacity(self.capacity, minimum)
    if capacity == 0 {
        return 0
    }

    let replacement = cast(i64*, malloc(capacity * 8))
    if !replacement {
        return 0
    }

    if self.length > 0 {
        memcpy(cast(u8*, replacement), cast(u8*, self.data), self.length * 8)
    }
    if self.data {
        free(cast(u8*, self.data))
    }

    self.data = replacement
    self.capacity = capacity
    return 1
}

let I64Vector:push = fn (self:I64Vector*, value:i64) -> i64 {
    if self.length == self.capacity {
        if self.reserve(self.length + 1) == 0 {
            return 0
        }
    }
    self.data[self.length] = value
    self.length += 1
    return 1
}

let I64Vector:extend = fn (self:I64Vector*, source:i64*, count:i64) -> i64 {
    if count < 0 {
        return 0
    }
    if count == 0 {
        return 1
    }

    // Preserve the common self-extend case across a reserve that may move data.
    let source_is_self = source == self.data
    if source_is_self && count > self.length {
        return 0
    }

    let old_length = self.length
    if self.reserve(old_length + count) == 0 {
        return 0
    }
    if source_is_self {
        source = self.data
    }
    memmove(cast(u8*, &self.data[old_length]), cast(u8*, source), count * 8)
    self.length = old_length + count
    return 1
}

let I64Vector:insert = fn (self:I64Vector*, index:i64, value:i64) -> i64 {
    if index < 0 || index > self.length {
        return 0
    }
    if self.length == self.capacity {
        if self.reserve(self.length + 1) == 0 {
            return 0
        }
    }

    if index < self.length {
        memmove(
            cast(u8*, &self.data[index + 1]),
            cast(u8*, &self.data[index]),
            (self.length - index) * 8
        )
    }
    self.data[index] = value
    self.length += 1
    return 1
}

let I64Vector:remove = fn (self:I64Vector*, index:i64, output:i64*) -> i64 {
    if index < 0 || index >= self.length {
        return 0
    }
    if output {
        output[0] = self.data[index]
    }

    if index + 1 < self.length {
        memmove(
            cast(u8*, &self.data[index]),
            cast(u8*, &self.data[index + 1]),
            (self.length - index - 1) * 8
        )
    }
    self.length -= 1
    return 1
}

let I64Vector:swap_remove = fn (self:I64Vector*, index:i64, output:i64*) -> i64 {
    if index < 0 || index >= self.length {
        return 0
    }
    if output {
        output[0] = self.data[index]
    }
    self.length -= 1
    if index != self.length {
        self.data[index] = self.data[self.length]
    }
    return 1
}

let I64Vector:pop = fn (self:I64Vector*, output:i64*) -> i64 {
    if self.length == 0 {
        return 0
    }
    self.length -= 1
    if output {
        output[0] = self.data[self.length]
    }
    return 1
}

let I64Vector:get = fn (self:I64Vector*, index:i64, output:i64*) -> i64 {
    if index < 0 || index >= self.length || !output {
        return 0
    }
    output[0] = self.data[index]
    return 1
}

let I64Vector:set_at = fn (self:I64Vector*, index:i64, value:i64) -> i64 {
    if index < 0 || index >= self.length {
        return 0
    }
    self.data[index] = value
    return 1
}

let I64Vector:clear = fn (self:I64Vector*) -> void {
    self.length = 0
}

let I64Vector:clone = fn (self:I64Vector*) -> I64Vector* {
    let copy = I64Vector:new(self.length)
    if !copy {
        return cast(I64Vector*, 0)
    }
    if self.length > 0 {
        memcpy(cast(u8*, copy.data), cast(u8*, self.data), self.length * 8)
    }
    copy.length = self.length
    return copy
}

let I64Vector:destroy = fn (self:I64Vector*) -> void {
    if !self {
        return
    }
    if self.data {
        free(cast(u8*, self.data))
    }
    free(cast(u8*, self))
}

// ============================================================================
// ByteVector - same generated layout, byte-oriented API.
// ============================================================================

let ByteVector:new = fn (initial_capacity:i64) -> ByteVector* {
    let self = cast(ByteVector*, malloc(24))
    if !self {
        return cast(ByteVector*, 0)
    }
    self.data = cast(u8*, 0)
    self.length = 0
    self.capacity = 0

    if initial_capacity > 0 {
        let capacity = Containers:next_capacity(0, initial_capacity)
        if capacity == 0 {
            free(cast(u8*, self))
            return cast(ByteVector*, 0)
        }
        self.data = malloc(capacity)
        if !self.data {
            free(cast(u8*, self))
            return cast(ByteVector*, 0)
        }
        self.capacity = capacity
    }
    return self
}

let ByteVector:reserve = fn (self:ByteVector*, minimum:i64) -> i64 {
    if minimum <= self.capacity {
        return 1
    }
    if minimum < 0 {
        return 0
    }

    let capacity = Containers:next_capacity(self.capacity, minimum)
    if capacity == 0 {
        return 0
    }
    let replacement = malloc(capacity)
    if !replacement {
        return 0
    }
    if self.length > 0 {
        memcpy(replacement, self.data, self.length)
    }
    if self.data {
        free(self.data)
    }
    self.data = replacement
    self.capacity = capacity
    return 1
}

let ByteVector:push = fn (self:ByteVector*, value:i64) -> i64 {
    if self.length == self.capacity {
        if self.reserve(self.length + 1) == 0 {
            return 0
        }
    }
    self.data[self.length] = cast(u8, value)
    self.length += 1
    return 1
}

let ByteVector:append = fn (self:ByteVector*, source:u8*, count:i64) -> i64 {
    if count < 0 {
        return 0
    }
    if count == 0 {
        return 1
    }

    let source_is_self = source == self.data
    if source_is_self && count > self.length {
        return 0
    }

    let old_length = self.length
    if self.reserve(old_length + count) == 0 {
        return 0
    }
    if source_is_self {
        source = self.data
    }
    memmove(&self.data[old_length], source, count)
    self.length = old_length + count
    return 1
}

let ByteVector:resize = fn (self:ByteVector*, length:i64, fill:i64) -> i64 {
    if length < 0 {
        return 0
    }
    if length > self.capacity && self.reserve(length) == 0 {
        return 0
    }
    while self.length < length {
        self.data[self.length] = cast(u8, fill)
        self.length += 1
    }
    if self.length > length {
        self.length = length
    }
    return 1
}

let ByteVector:clear = fn (self:ByteVector*) -> void {
    self.length = 0
}

let ByteVector:destroy = fn (self:ByteVector*) -> void {
    if !self {
        return
    }
    if self.data {
        free(self.data)
    }
    free(cast(u8*, self))
}

// ============================================================================
// String - owned zero-terminated byte string composed from ByteVector.
// ============================================================================

record Containers:String {
    storage:ByteVector*
}

let Containers:text_length = fn (text:u8*) -> i64 {
    var length = 0
    while text[length] != 0 {
        length += 1
    }
    return length
}

let Containers:text_equals_bytes = fn (left:u8*, right:u8*, length:i64) -> i64 {
    var index = 0
    while index < length {
        if left[index] != right[index] {
            return 0
        }
        index += 1
    }
    return 1
}

let Containers:String:with_capacity = fn (capacity:i64) -> Containers:String* {
    let self = cast(Containers:String*, malloc(8))
    if !self {
        return cast(Containers:String*, 0)
    }

    self.storage = ByteVector:new(capacity + 1)
    if !self.storage {
        free(cast(u8*, self))
        return cast(Containers:String*, 0)
    }

    if self.storage.reserve(1) == 0 {
        self.storage.destroy()
        free(cast(u8*, self))
        return cast(Containers:String*, 0)
    }
    self.storage.data[0] = 0
    return self
}

let Containers:String:new = fn (text:u8*) -> Containers:String* {
    let length = Containers:text_length(text)
    let self = Containers:String:with_capacity(length)
    if !self {
        return cast(Containers:String*, 0)
    }

    if length > 0 && self.storage.append(text, length) == 0 {
        self.storage.destroy()
        free(cast(u8*, self))
        return cast(Containers:String*, 0)
    }
    if self.storage.reserve(self.storage.length + 1) == 0 {
        self.storage.destroy()
        free(cast(u8*, self))
        return cast(Containers:String*, 0)
    }
    self.storage.data[self.storage.length] = 0
    return self
}

let Containers:String:len = fn (self:String*) -> i64 {
    return self.storage.length
}

let Containers:String:c_str = fn (self:String*) -> u8* {
    return self.storage.data
}

let Containers:String:append_bytes = fn (self:String*, text:u8*, length:i64) -> i64 {
    if length < 0 {
        return 0
    }

    let source_is_self = text == self.storage.data
    if source_is_self && length > self.storage.length {
        return 0
    }

    let old_length = self.storage.length
    if self.storage.reserve(old_length + length + 1) == 0 {
        return 0
    }
    if source_is_self {
        text = self.storage.data
    }
    if length > 0 {
        memmove(&self.storage.data[old_length], text, length)
        self.storage.length = old_length + length
    }
    self.storage.data[self.storage.length] = 0
    return 1
}

let Containers:String:append = fn (self:String*, text:u8*) -> i64 {
    return self.append_bytes(text, Containers:text_length(text))
}

let Containers:String:push = fn (self:String*, value:i64) -> i64 {
    if self.storage.reserve(self.storage.length + 2) == 0 {
        return 0
    }
    self.storage.data[self.storage.length] = cast(u8, value)
    self.storage.length += 1
    self.storage.data[self.storage.length] = 0
    return 1
}

let Containers:String:clear = fn (self:String*) -> void {
    self.storage.clear()
    if self.storage.capacity > 0 {
        self.storage.data[0] = 0
    }
}

let Containers:String:equals = fn (self:String*, text:u8*) -> i64 {
    let other_length = Containers:text_length(text)
    if other_length != self.storage.length {
        return 0
    }
    return Containers:text_equals_bytes(self.storage.data, text, other_length)
}

let Containers:String:destroy = fn (self:String*) -> void {
    if !self {
        return
    }
    if self.storage {
        self.storage.destroy()
    }
    free(cast(u8*, self))
}

// ============================================================================
// Arena - chunked bump allocator with alignment and stable pointers.
// ============================================================================

record Containers:ArenaBlock {
    next:Containers:ArenaBlock*
    data:u8*
    used:i64
    capacity:i64
}

record Containers:Arena {
    head:Containers:ArenaBlock*
    default_capacity:i64
    allocations:i64
    blocks:i64
    bytes_used:i64
}

let Containers:Arena:new = fn (default_capacity:i64) -> Containers:Arena* {
    var capacity = default_capacity
    if capacity < 256 {
        capacity = 256
    }

    let self = cast(Containers:Arena*, malloc(40))
    if !self {
        return cast(Containers:Arena*, 0)
    }

    self.head = cast(Containers:ArenaBlock*, 0)
    self.default_capacity = capacity
    self.allocations = 0
    self.blocks = 0
    self.bytes_used = 0
    return self
}

let Containers:Arena:add_block = fn (self:Arena*, minimum_capacity:i64) -> i64 {
    var capacity = self.default_capacity
    if capacity < minimum_capacity {
        capacity = minimum_capacity
    }

    let block = cast(Containers:ArenaBlock*, malloc(32))
    if !block {
        return 0
    }

    block.data = malloc(capacity)
    if !block.data {
        free(cast(u8*, block))
        return 0
    }

    block.next = self.head
    block.used = 0
    block.capacity = capacity
    self.head = block
    self.blocks += 1
    return 1
}

let Containers:Arena:alloc_aligned = fn (self:Arena*, bytes:i64, alignment:i64) -> u8* {
    if bytes <= 0 {
        return cast(u8*, 0)
    }

    var align = alignment
    if align < 1 {
        align = 1
    }

    // The public container API only requests power-of-two alignments. Reject
    // invalid values instead of silently returning a misaligned address.
    // malloc guarantees enough base alignment for the scalar/pointer records
    // used here; keep the public contract conservative and explicit.
    if align != 1 && align != 2 && align != 4 && align != 8 {
        return cast(u8*, 0)
    }

    if !self.head {
        if self.add_block(bytes + align) == 0 {
            return cast(u8*, 0)
        }
    }

    var aligned_used = ((self.head.used + align - 1) / align) * align
    if aligned_used + bytes > self.head.capacity {
        if self.add_block(bytes + align) == 0 {
            return cast(u8*, 0)
        }
        aligned_used = 0
    }

    let memory = &self.head.data[aligned_used]
    self.head.used = aligned_used + bytes
    self.allocations += 1
    self.bytes_used += bytes
    return memory
}

let Containers:Arena:alloc = fn (self:Arena*, bytes:i64) -> u8* {
    return self.alloc_aligned(bytes, 8)
}

let Containers:Arena:copy_bytes = fn (self:Arena*, source:u8*, length:i64, zero_terminate:i64) -> u8* {
    if length < 0 {
        return cast(u8*, 0)
    }

    var extra = 0
    if zero_terminate {
        extra = 1
    }
    let target = self.alloc_aligned(length + extra, 1)
    if !target {
        return cast(u8*, 0)
    }
    if length > 0 {
        memcpy(target, source, length)
    }
    if zero_terminate {
        target[length] = 0
    }
    return target
}

let Containers:Arena:copy_text = fn (self:Arena*, source:u8*, length:i64) -> u8* {
    return self.copy_bytes(source, length, 1)
}

let Containers:Arena:reset = fn (self:Arena*) -> void {
    var block = self.head
    while block {
        let next = block.next
        free(block.data)
        free(cast(u8*, block))
        block = next
    }
    self.head = cast(Containers:ArenaBlock*, 0)
    self.allocations = 0
    self.blocks = 0
    self.bytes_used = 0
}

let Containers:Arena:destroy = fn (self:Arena*) -> void {
    if !self {
        return
    }
    self.reset()
    free(cast(u8*, self))
}

// ============================================================================
// StringInterner - open-addressed table whose entries and strings live in Arena.
// Returned entry pointers stay stable through table rehashes.
// ============================================================================

record Containers:InternEntry {
    text:u8*
    length:i64
    hash:i64
    id:i64
}

record Containers:StringInterner {
    slots:Containers:InternEntry**
    length:i64
    capacity:i64
    next_id:i64
    arena:Containers:Arena*
}

let Containers:hash_bytes = fn (text:u8*, length:i64) -> i64 {
    var hash = 5381
    var index = 0
    while index < length {
        hash = (hash * 131 + text[index]) % 2147483647
        index += 1
    }
    if hash < 0 {
        hash = -hash
    }
    return hash
}

let Containers:StringInterner:new = fn (arena:Arena*, initial_capacity:i64) -> Containers:StringInterner* {
    var capacity = Containers:next_capacity(0, initial_capacity)
    if capacity == 0 {
        capacity = 8
    }

    let self = cast(Containers:StringInterner*, malloc(40))
    if !self {
        return cast(Containers:StringInterner*, 0)
    }

    self.slots = cast(Containers:InternEntry**, malloc(capacity * 8))
    if !self.slots {
        free(cast(u8*, self))
        return cast(Containers:StringInterner*, 0)
    }

    var index = 0
    while index < capacity {
        self.slots[index] = cast(Containers:InternEntry*, 0)
        index += 1
    }

    self.length = 0
    self.capacity = capacity
    self.next_id = 1
    self.arena = arena
    return self
}

let Containers:StringInterner:insert_existing = fn (self:StringInterner*, entry:InternEntry*) -> void {
    var slot = entry.hash % self.capacity
    while self.slots[slot] {
        slot = (slot + 1) % self.capacity
    }
    self.slots[slot] = entry
}

let Containers:StringInterner:rehash = fn (self:StringInterner*, minimum_capacity:i64) -> i64 {
    let capacity = Containers:next_capacity(self.capacity, minimum_capacity)
    if capacity == 0 || capacity <= self.capacity {
        return 0
    }

    let replacement = cast(Containers:InternEntry**, malloc(capacity * 8))
    if !replacement {
        return 0
    }

    var index = 0
    while index < capacity {
        replacement[index] = cast(Containers:InternEntry*, 0)
        index += 1
    }

    let old_slots = self.slots
    let old_capacity = self.capacity
    self.slots = replacement
    self.capacity = capacity

    index = 0
    while index < old_capacity {
        let entry = old_slots[index]
        if entry {
            self.insert_existing(entry)
        }
        index += 1
    }

    free(cast(u8*, old_slots))
    return 1
}

let Containers:StringInterner:intern_bytes = fn (self:StringInterner*, source:u8*, length:i64) -> Containers:InternEntry* {
    if length < 0 {
        return cast(Containers:InternEntry*, 0)
    }

    if (self.length + 1) * 10 >= self.capacity * 7 {
        if self.rehash(self.capacity * 2) == 0 {
            return cast(Containers:InternEntry*, 0)
        }
    }

    let hash = Containers:hash_bytes(source, length)
    var slot = hash % self.capacity
    var probes = 0

    while probes < self.capacity {
        let existing = self.slots[slot]
        if !existing {
            let text = self.arena.copy_text(source, length)
            if !text {
                return cast(Containers:InternEntry*, 0)
            }

            let entry = cast(Containers:InternEntry*, self.arena.alloc_aligned(32, 8))
            if !entry {
                return cast(Containers:InternEntry*, 0)
            }
            entry.text = text
            entry.length = length
            entry.hash = hash
            entry.id = self.next_id
            self.next_id += 1

            self.slots[slot] = entry
            self.length += 1
            return entry
        }

        if existing.hash == hash && existing.length == length && Containers:text_equals_bytes(existing.text, source, length) {
            return existing
        }

        slot = (slot + 1) % self.capacity
        probes += 1
    }

    return cast(Containers:InternEntry*, 0)
}

let Containers:StringInterner:intern = fn (self:StringInterner*, text:u8*) -> Containers:InternEntry* {
    return self.intern_bytes(text, Containers:text_length(text))
}

let Containers:StringInterner:lookup_bytes = fn (self:StringInterner*, source:u8*, length:i64) -> Containers:InternEntry* {
    let hash = Containers:hash_bytes(source, length)
    var slot = hash % self.capacity
    var probes = 0

    while probes < self.capacity {
        let existing = self.slots[slot]
        if !existing {
            return cast(Containers:InternEntry*, 0)
        }
        if existing.hash == hash && existing.length == length && Containers:text_equals_bytes(existing.text, source, length) {
            return existing
        }
        slot = (slot + 1) % self.capacity
        probes += 1
    }
    return cast(Containers:InternEntry*, 0)
}

let Containers:StringInterner:lookup = fn (self:StringInterner*, text:u8*) -> Containers:InternEntry* {
    return self.lookup_bytes(text, Containers:text_length(text))
}

let Containers:StringInterner:destroy = fn (self:StringInterner*) -> void {
    if !self {
        return
    }
    if self.slots {
        free(cast(u8*, self.slots))
    }
    free(cast(u8*, self))
}

// ============================================================================
// I64HashMap - open addressing with tombstones and automatic compaction.
// ============================================================================

record Containers:I64MapEntry {
    key:i64
    value:i64
    state:i64
}

record Containers:I64HashMap {
    entries:Containers:I64MapEntry*
    length:i64
    capacity:i64
    tombstones:i64
}

let Containers:hash_i64 = fn (value:i64) -> i64 {
    var x = value % 2147483647
    if x < 0 {
        x = -x
    }
    x = (x * 131 + 17) % 2147483647
    x = (x * 131 + 97) % 2147483647
    return x
}

let Containers:I64HashMap:new = fn (initial_capacity:i64) -> Containers:I64HashMap* {
    var capacity = Containers:next_capacity(0, initial_capacity)
    if capacity == 0 {
        capacity = 8
    }

    let self = cast(Containers:I64HashMap*, malloc(32))
    if !self {
        return cast(Containers:I64HashMap*, 0)
    }

    self.entries = cast(Containers:I64MapEntry*, malloc(capacity * 24))
    if !self.entries {
        free(cast(u8*, self))
        return cast(Containers:I64HashMap*, 0)
    }

    var index = 0
    while index < capacity {
        self.entries[index].state = 0
        index += 1
    }

    self.length = 0
    self.capacity = capacity
    self.tombstones = 0
    return self
}

let Containers:I64HashMap:insert_without_growth = fn (self:I64HashMap*, key:i64, value:i64) -> i64 {
    var slot = Containers:hash_i64(key) % self.capacity
    var first_tombstone = -1
    var probes = 0

    while probes < self.capacity {
        let state = self.entries[slot].state
        if state == 0 {
            var destination = slot
            if first_tombstone >= 0 {
                destination = first_tombstone
                self.tombstones -= 1
            }
            self.entries[destination].key = key
            self.entries[destination].value = value
            self.entries[destination].state = 1
            self.length += 1
            return 1
        }

        if state == 1 && self.entries[slot].key == key {
            self.entries[slot].value = value
            return 1
        }

        if state == 2 && first_tombstone < 0 {
            first_tombstone = slot
        }

        slot = (slot + 1) % self.capacity
        probes += 1
    }

    if first_tombstone >= 0 {
        self.entries[first_tombstone].key = key
        self.entries[first_tombstone].value = value
        self.entries[first_tombstone].state = 1
        self.length += 1
        self.tombstones -= 1
        return 1
    }
    return 0
}

let Containers:I64HashMap:rehash = fn (self:I64HashMap*, requested_capacity:i64) -> i64 {
    var capacity = Containers:next_capacity(0, requested_capacity)
    if capacity < 8 {
        capacity = 8
    }

    let replacement = cast(Containers:I64MapEntry*, malloc(capacity * 24))
    if !replacement {
        return 0
    }

    var index = 0
    while index < capacity {
        replacement[index].state = 0
        index += 1
    }

    let old_entries = self.entries
    let old_capacity = self.capacity
    self.entries = replacement
    self.capacity = capacity
    self.length = 0
    self.tombstones = 0

    index = 0
    while index < old_capacity {
        if old_entries[index].state == 1 {
            if self.insert_without_growth(old_entries[index].key, old_entries[index].value) == 0 {
                // This cannot occur with a same-or-larger power-of-two table.
                free(cast(u8*, old_entries))
                return 0
            }
        }
        index += 1
    }

    free(cast(u8*, old_entries))
    return 1
}

let Containers:I64HashMap:put = fn (self:I64HashMap*, key:i64, value:i64) -> i64 {
    if (self.length + self.tombstones + 1) * 10 >= self.capacity * 7 {
        if self.rehash(self.capacity * 2) == 0 {
            return 0
        }
    }
    return self.insert_without_growth(key, value)
}

let Containers:I64HashMap:get = fn (self:I64HashMap*, key:i64, output:i64*) -> i64 {
    var slot = Containers:hash_i64(key) % self.capacity
    var probes = 0

    while probes < self.capacity {
        let state = self.entries[slot].state
        if state == 0 {
            return 0
        }
        if state == 1 && self.entries[slot].key == key {
            if output {
                output[0] = self.entries[slot].value
            }
            return 1
        }
        slot = (slot + 1) % self.capacity
        probes += 1
    }
    return 0
}

let Containers:I64HashMap:contains = fn (self:I64HashMap*, key:i64) -> i64 {
    return self.get(key, cast(i64*, 0))
}

let Containers:I64HashMap:remove = fn (self:I64HashMap*, key:i64, output:i64*) -> i64 {
    var slot = Containers:hash_i64(key) % self.capacity
    var probes = 0

    while probes < self.capacity {
        let state = self.entries[slot].state
        if state == 0 {
            return 0
        }
        if state == 1 && self.entries[slot].key == key {
            if output {
                output[0] = self.entries[slot].value
            }
            self.entries[slot].state = 2
            self.length -= 1
            self.tombstones += 1

            // Compact pathological tombstone-heavy tables without changing the
            // externally visible capacity.
            if self.tombstones > self.length && self.tombstones > 8 {
                if self.rehash(self.capacity) == 0 {
                    return 1
                }
            }
            return 1
        }
        slot = (slot + 1) % self.capacity
        probes += 1
    }
    return 0
}

let Containers:I64HashMap:clear = fn (self:I64HashMap*) -> void {
    var index = 0
    while index < self.capacity {
        self.entries[index].state = 0
        index += 1
    }
    self.length = 0
    self.tombstones = 0
}

let Containers:I64HashMap:destroy = fn (self:I64HashMap*) -> void {
    if !self {
        return
    }
    if self.entries {
        free(cast(u8*, self.entries))
    }
    free(cast(u8*, self))
}

// ============================================================================
// I64Deque - growable ring buffer with stable FIFO/LIFO semantics.
// ============================================================================

record Containers:I64Deque {
    data:i64*
    head:i64
    length:i64
    capacity:i64
}

let Containers:I64Deque:new = fn (initial_capacity:i64) -> Containers:I64Deque* {
    let self = cast(Containers:I64Deque*, malloc(32))
    if !self {
        return cast(Containers:I64Deque*, 0)
    }

    self.data = cast(i64*, 0)
    self.head = 0
    self.length = 0
    self.capacity = 0

    if initial_capacity > 0 {
        let capacity = Containers:next_capacity(0, initial_capacity)
        if capacity == 0 {
            free(cast(u8*, self))
            return cast(Containers:I64Deque*, 0)
        }
        self.data = cast(i64*, malloc(capacity * 8))
        if !self.data {
            free(cast(u8*, self))
            return cast(Containers:I64Deque*, 0)
        }
        self.capacity = capacity
    }
    return self
}

let Containers:I64Deque:reserve = fn (self:I64Deque*, minimum:i64) -> i64 {
    if minimum <= self.capacity {
        return 1
    }
    let capacity = Containers:next_capacity(self.capacity, minimum)
    if capacity == 0 {
        return 0
    }

    let replacement = cast(i64*, malloc(capacity * 8))
    if !replacement {
        return 0
    }

    var index = 0
    while index < self.length {
        replacement[index] = self.data[(self.head + index) % self.capacity]
        index += 1
    }

    if self.data {
        free(cast(u8*, self.data))
    }
    self.data = replacement
    self.head = 0
    self.capacity = capacity
    return 1
}

let Containers:I64Deque:push_back = fn (self:I64Deque*, value:i64) -> i64 {
    if self.length == self.capacity {
        if self.reserve(self.length + 1) == 0 {
            return 0
        }
    }
    let slot = (self.head + self.length) % self.capacity
    self.data[slot] = value
    self.length += 1
    return 1
}

let Containers:I64Deque:push_front = fn (self:I64Deque*, value:i64) -> i64 {
    if self.length == self.capacity {
        if self.reserve(self.length + 1) == 0 {
            return 0
        }
    }
    self.head = (self.head + self.capacity - 1) % self.capacity
    self.data[self.head] = value
    self.length += 1
    return 1
}

let Containers:I64Deque:pop_front = fn (self:I64Deque*, output:i64*) -> i64 {
    if self.length == 0 {
        return 0
    }
    if output {
        output[0] = self.data[self.head]
    }
    self.head = (self.head + 1) % self.capacity
    self.length -= 1
    if self.length == 0 {
        self.head = 0
    }
    return 1
}

let Containers:I64Deque:pop_back = fn (self:I64Deque*, output:i64*) -> i64 {
    if self.length == 0 {
        return 0
    }
    let slot = (self.head + self.length - 1) % self.capacity
    if output {
        output[0] = self.data[slot]
    }
    self.length -= 1
    if self.length == 0 {
        self.head = 0
    }
    return 1
}

let Containers:I64Deque:peek_front = fn (self:I64Deque*, output:i64*) -> i64 {
    if self.length == 0 || !output {
        return 0
    }
    output[0] = self.data[self.head]
    return 1
}

let Containers:I64Deque:peek_back = fn (self:I64Deque*, output:i64*) -> i64 {
    if self.length == 0 || !output {
        return 0
    }
    output[0] = self.data[(self.head + self.length - 1) % self.capacity]
    return 1
}

let Containers:I64Deque:destroy = fn (self:I64Deque*) -> void {
    if !self {
        return
    }
    if self.data {
        free(cast(u8*, self.data))
    }
    free(cast(u8*, self))
}

// ============================================================================
// Composition example: tokenize -> intern -> frequency map -> order vector ->
// processing queue. Scratch bytes use ByteVector, persistent strings use Arena.
// ============================================================================

let Containers:is_word_character = fn (value:i64) -> i64 {
    if value >= 48 && value <= 57 {
        return 1
    }
    if value >= 65 && value <= 90 {
        return 1
    }
    if value >= 97 && value <= 122 {
        return 1
    }
    return value == 95
}

let Containers:lower_ascii = fn (value:i64) -> i64 {
    if value >= 65 && value <= 90 {
        return value + 32
    }
    return value
}

let Containers:index_words = fn (
    source:u8*,
    interner:StringInterner*,
    frequencies:I64HashMap*,
    order:I64Vector*,
    queue:I64Deque*
) -> i64 {
    let scratch = ByteVector:new(32)
    if !scratch {
        return -1
    }
    defer scratch.destroy()

    let source_length = Containers:text_length(source)
    var source_index = 0
    var words = 0

    while source_index <= source_length {
        let character = source[source_index]
        if Containers:is_word_character(character) {
            if scratch.push(Containers:lower_ascii(character)) == 0 {
                return -1
            }
        } else {
            if scratch.length > 0 {
                let entry = interner.intern_bytes(scratch.data, scratch.length)
                if !entry {
                    return -1
                }

                var count = 0
                if frequencies.get(entry.id, &count) {
                    count += 1
                } else {
                    count = 1
                }
                if frequencies.put(entry.id, count) == 0 {
                    return -1
                }
                if order.push(entry.id) == 0 {
                    return -1
                }
                if queue.push_back(entry.id) == 0 {
                    return -1
                }

                scratch.clear()
                words += 1
            }
        }
        source_index += 1
    }

    return words
}

// ============================================================================
// Runtime self-tests. Each function returns 0 on success or a precise code.
// ============================================================================

let Containers:test_vectors = fn () -> i64 {
    let values = I64Vector:new(0)
    if !values {
        return 101
    }
    defer values.destroy()

    var index = 0
    while index < 512 {
        if values.push(index * 3) == 0 {
            return 102
        }
        index += 1
    }

    if values.length != 512 || values.capacity < 512 {
        return 103
    }

    if values.insert(0, -1) == 0 || values.insert(257, 777777) == 0 || values.insert(values.length, -2) == 0 {
        return 104
    }

    var removed = 0
    if values.remove(257, &removed) == 0 || removed != 777777 {
        return 105
    }
    if values.remove(0, &removed) == 0 || removed != -1 {
        return 106
    }
    if values.pop(&removed) == 0 || removed != -2 {
        return 107
    }

    // Force self-extension through a growth boundary. The source pointer must
    // be rebound after reserve rather than referencing freed storage.
    let before_extend = values.length
    if values.extend(values.data, values.length) == 0 {
        return 108
    }
    if values.length != before_extend * 2 || values.data[before_extend + 17] != values.data[17] {
        return 109
    }

    let copy = values.clone()
    if !copy {
        return 110
    }
    defer copy.destroy()

    if copy.length != values.length || copy.data[511] != values.data[511] {
        return 111
    }
    copy.data[0] = 999
    if values.data[0] == 999 {
        return 112
    }

    var fast_removed = 0
    if copy.swap_remove(10, &fast_removed) == 0 {
        return 113
    }
    if copy.length != values.length - 1 {
        return 114
    }

    return 0
}

let Containers:test_string = fn () -> i64 {
    let text = Containers:String:new("Recur")
    if !text {
        return 201
    }
    defer text.destroy()

    if text.append("Loop") == 0 || text.push(32) == 0 || text.append("containers") == 0 {
        return 202
    }
    if !text.equals("RecurLoop containers") {
        return 203
    }
    if text.len() != 20 || text.c_str()[20] != 0 {
        return 204
    }

    if text.append_bytes(text.c_str(), text.len()) == 0 {
        return 205
    }
    if text.len() != 40 || !text.equals("RecurLoop containersRecurLoop containers") {
        return 206
    }

    text.clear()
    if text.len() != 0 || text.c_str()[0] != 0 {
        return 207
    }
    if text.append("production") == 0 || !text.equals("production") {
        return 208
    }
    return 0
}

let Containers:test_hash_map = fn () -> i64 {
    let map = Containers:I64HashMap:new(2)
    if !map {
        return 301
    }
    defer map.destroy()

    var key = 0
    while key < 300 {
        if map.put(key, key * 7 + 3) == 0 {
            return 302
        }
        key += 1
    }
    if map.length != 300 || map.capacity < 512 {
        return 303
    }

    key = 0
    while key < 300 {
        var value = 0
        if map.get(key, &value) == 0 || value != key * 7 + 3 {
            return 304
        }
        key += 1
    }

    // Remove enough keys to force tombstone compaction at least once.
    key = 0
    while key < 220 {
        var removed = 0
        if map.remove(key, &removed) == 0 || removed != key * 7 + 3 {
            return 305
        }
        key += 1
    }
    if map.length != 80 {
        return 306
    }

    key = 0
    while key < 220 {
        if map.contains(key) {
            return 307
        }
        key += 1
    }

    key = 0
    while key < 220 {
        if map.put(key, 100000 + key) == 0 {
            return 308
        }
        key += 1
    }
    if map.length != 300 {
        return 309
    }

    var updated = 0
    if map.get(42, &updated) == 0 || updated != 100042 {
        return 310
    }
    return 0
}

let Containers:test_deque = fn () -> i64 {
    let queue = Containers:I64Deque:new(4)
    if !queue {
        return 401
    }
    defer queue.destroy()

    var value = 0
    while value < 100 {
        if queue.push_back(value) == 0 {
            return 402
        }
        value += 1
    }

    // Move the head deep into the ring, then append again to force wrap-around.
    value = 0
    while value < 70 {
        var popped = 0
        if queue.pop_front(&popped) == 0 || popped != value {
            return 403
        }
        value += 1
    }

    value = 100
    while value < 180 {
        if queue.push_back(value) == 0 {
            return 404
        }
        value += 1
    }

    if queue.push_front(69) == 0 || queue.push_front(68) == 0 {
        return 405
    }

    var expected = 68
    while queue.length > 0 {
        var popped = 0
        if queue.pop_front(&popped) == 0 || popped != expected {
            return 406
        }
        expected += 1
    }
    if expected != 180 {
        return 407
    }

    if queue.pop_front(&value) || queue.pop_back(&value) {
        return 408
    }
    return 0
}

let Containers:test_composition = fn () -> i64 {
    let arena = Containers:Arena:new(128)
    if !arena {
        return 501
    }
    defer arena.destroy()

    let interner = Containers:StringInterner:new(arena, 4)
    if !interner {
        return 502
    }
    defer interner.destroy()

    let frequencies = Containers:I64HashMap:new(4)
    if !frequencies {
        return 503
    }
    defer frequencies.destroy()

    let order = I64Vector:new(4)
    if !order {
        return 504
    }
    defer order.destroy()

    let queue = Containers:I64Deque:new(4)
    if !queue {
        return 505
    }
    defer queue.destroy()

    let words = Containers:index_words(
        "RecurLoop vector map queue arena string interner allocator stable fast vector map queue containers production language runtime memory vector map",
        interner,
        frequencies,
        order,
        queue
    )
    if words != 20 {
        return 506
    }
    if order.length != 20 || queue.length != 20 || interner.length != 15 {
        return 507
    }

    let vector_word = interner.lookup("vector")
    let map_word = interner.lookup("map")
    let queue_word = interner.lookup("queue")
    let recurloop_word = interner.lookup("recurloop")
    let missing = interner.lookup("missing")
    if !vector_word || !map_word || !queue_word || !recurloop_word || missing {
        return 508
    }

    var count = 0
    if frequencies.get(vector_word.id, &count) == 0 || count != 3 {
        return 509
    }
    if frequencies.get(map_word.id, &count) == 0 || count != 3 {
        return 510
    }
    if frequencies.get(queue_word.id, &count) == 0 || count != 2 {
        return 511
    }
    if frequencies.get(recurloop_word.id, &count) == 0 || count != 1 {
        return 512
    }

    // Canonical identity must survive both interner rehashes.
    if interner.intern("vector") != vector_word {
        return 513
    }

    var processed = 0
    var first_id = 0
    while queue.length > 0 {
        var id = 0
        if queue.pop_front(&id) == 0 {
            return 514
        }
        if processed == 0 {
            first_id = id
        }
        processed += 1
    }
    if processed != 20 || first_id != recurloop_word.id {
        return 515
    }

    if arena.blocks < 2 || arena.allocations < 30 {
        // 15 text copies + 15 entry records should force multiple blocks when
        // the requested default size is clamped to 256 bytes.
        return 516
    }

    printf(
        "composition: words=%lld unique=%lld vector=%lld map=%lld queue=%lld arena_blocks=%lld arena_allocations=%lld\n",
        words,
        interner.length,
        3,
        3,
        2,
        arena.blocks,
        arena.allocations
    )
    return 0
}

// ============================================================================
// Final executable.
// ============================================================================

emit executable "/tmp/recurloop-containers-production" containers_main = fn () -> i64 {
    printf("RecurLoop production containers example\n")

    let vector_result = Containers:test_vectors()
    if vector_result != 0 {
        printf("vector test failed: %lld\n", vector_result)
        return vector_result
    }
    printf("vector: generated type + reserve/insert/remove/clone OK\n")

    let string_result = Containers:test_string()
    if string_result != 0 {
        printf("string test failed: %lld\n", string_result)
        return string_result
    }
    printf("string: ByteVector-backed ownership + NUL invariant OK\n")

    let map_result = Containers:test_hash_map()
    if map_result != 0 {
        printf("hash map test failed: %lld\n", map_result)
        return map_result
    }
    printf("hash map: growth/update/remove/tombstone compaction OK\n")

    let deque_result = Containers:test_deque()
    if deque_result != 0 {
        printf("deque test failed: %lld\n", deque_result)
        return deque_result
    }
    printf("deque: ring wrap-around + growth + front/back operations OK\n")

    let composition_result = Containers:test_composition()
    if composition_result != 0 {
        printf("composition test failed: %lld\n", composition_result)
        return composition_result
    }

    printf("all production container checks passed\n")
    return 0
}

debug:stats
