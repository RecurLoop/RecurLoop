```recurloop
let name = expression
```

Defines a phrase or runtime binding according to its definition.

With Shell loaded, a right-hand side beginning with `run` or `capture` stores its result. Other definitions retain core behavior.

**Example**

```recurloop
let output = capture echo "hello"
```


