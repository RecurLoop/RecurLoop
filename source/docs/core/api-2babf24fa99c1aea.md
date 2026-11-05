```recurloop
if condition { ... } else { ... }
```

Runs the first block when the condition is true, otherwise the optional `else` block. Inside compiled functions, `else if` chains further conditions.

**Example**

```recurloop
if count > 0 { print "ready" } else { print "empty" }
```


