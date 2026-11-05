Compile a typed function.

Route callback receiving a borrowed request and response. Send a response before returning; do not destroy these handler arguments.

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
