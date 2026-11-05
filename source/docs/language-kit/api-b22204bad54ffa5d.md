Compile a typed function.

Compiles a typed function. Parameters use name:type; void returns no value. Omit the body to define a reusable signature. Call with name(arguments).

## Syntax

```recurloop
[<name:id>] "(" <parameters:raw> ")" "->" <result:qualified-id> [<body:block>]
```

## Example

```recurloop
fn add(a:i64, b:i64) -> i64 { return a + b }
```

## Arguments

- ** ** — 
- **:** — 
- **body** — Statements in braces. return supplies the result.
- **parameters** — Comma-separated name:type pairs; leave empty for no parameters.
- **result** — Return type; use void when no value is returned.
