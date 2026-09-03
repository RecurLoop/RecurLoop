# Lexicon

The lexicon gives semantic meaning to radix entries. `lexicon::Lexicon`
extends `radix::Radix`; `Dictionary` wraps a radix node, and `Phrase` wraps an
item attached to that node.

## Phrase model

A phrase can own these optional fields:

- parent dictionary;
- nested subdictionary;
- prototype;
- type;
- successor;
- action binding;
- serializable payload.

The metadata contains presence flags, so an explicitly empty slot differs from
an absent slot. This matters for mutation and image restoration.

An action binding contains host dispatch, an optional phrase implementation,
and a process-local native entry. Only relocatable parts are serialized.

## Construction

`Draft` builds a phrase before it is committed. It can start from a dictionary,
prototype, existing phrase, or action. `save()` writes cached metadata into the
flat store; `load()` reconstructs the cached view.

Phrase payload is append-only within the radix allocation model. Typed helper
methods read and update fixed-size fields, while the public language API offers
bounded byte-oriented access.

## Lookup

`matchExact`, `matchFirst`, and `matchLongest` are forwarded from dictionaries
to the radix layer and return `lexicon::Match`. Language execution normally
uses longest matching.

Prototype and parent traversal are separate:

- parent links define dictionary ownership and lexical name lookup;
- prototype links provide inherited behavior and structure;
- successor links support grammar sequencing.

## Dispatch

Phrase types resolve elaborate and invoke behavior. A callable phrase is
invoked as a command or function; an elaboratable phrase can consume and
rewrite source before normal execution. Exceptions captured across a native
frame are rethrown at the phrase boundary.

See [radix-tree.md](radix-tree.md), [context.md](context.md), and
[engine-images.md](engine-images.md).
