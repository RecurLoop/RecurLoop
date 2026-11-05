Define a function, alias, dictionary or phrase.

```recurloop
struct Name = [ key = definition ... ]
```

Defines a phrase dictionary through the same grammar as `let`. Children are accessed with `Name:key`; use `record` for native data layout.

## Syntax

```recurloop
<name:qualified-id> = <definition:raw>
```

## Example

```recurloop
let say = <print>
```

## Arguments

- ** ** — 
- **:** — 
- **definition** — fn, phrase, a reference <name> or a dictionary [...]. Inside fn, let also binds expression values.
- **name** — New name; qualify it with a dictionary, e.g. Tools:say.
