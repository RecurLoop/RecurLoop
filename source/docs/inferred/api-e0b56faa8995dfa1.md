```recurloop
infer fn name(parameter, ...) { ... }
infer { ... }
```

Selects Inferred syntax explicitly. Parameters and result types may be inferred; the block form applies this selection to its contents.

**Example**

```recurloop
infer fn twice(x) { return x + x }
```


