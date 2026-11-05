```recurloop
defer cleanup_expression
```

In a compiled function, registers cleanup for exit. Deferred expressions run in reverse registration order, including when returning early.

**Example (inside fn)**

```recurloop
let buffer = alloc(u8[64])
defer free(buffer)
```


