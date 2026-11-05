Repeat while the condition is true.

```recurloop
while condition { ... }
```

Repeats the block while the condition is true. The condition is checked before each iteration.

**Example**

```recurloop
var n = 0
while n < 3 {
    print n
    n += 1
}
```

## Syntax

```recurloop
<condition:expr> <body:block>
```

## Example

```recurloop
while count < 3 { count += 1 }
```

## Arguments

- ** ** — 
- **:** — 
- **body** — Update the condition or use break to end the loop.
- **condition** — Checked before each iteration.
