# Radix tree

The radix layer stores arbitrary bit-string keys and supports the matching rule
used by the language parser.

## Storage

`radix::Radix` operates on a flat memory buffer. Nodes and items are referenced
by `Size` offsets into that buffer, never by stored C++ pointers. `Meta` tracks
the allocation boundary and root state.

- `Node` represents a key path and can own items or child nodes.
- `Item` stores payload attached to a node.
- `Match` adds matched-bit length and whether more input could match.
- `Checkpoint` captures an address for rollback.

Keys are bit-aware. A key may end between byte boundaries; unused low bits in
the last byte must be zero. String helpers simply use byte-aligned keys.

## Operations

`Node::append` creates or finds a path. `push` appends an item. Matching modes:

- `matchExact` requires the complete key;
- `matchFirst` returns the first accepted match;
- `matchLongest` returns the most specific accepted match.

Filters allow higher layers to ignore nodes or items that do not represent the
required semantic object.

Forward, reverse, predecessor, and chronological traversal support dictionary
iteration and rollback-aware lookup. Allocation and traversal remain valid
after buffer relocation because stored relationships are offsets.

## Role in the language

The lexicon maps radix items to phrases. `Context::Source` passes the remaining
source bits to the active dictionary and normally requests the longest match.
This makes multi-character operators, keywords, arbitrary phrase names, and
source-defined syntax use the same mechanism.
