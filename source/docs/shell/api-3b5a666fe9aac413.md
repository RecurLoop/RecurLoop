Adds a text-transforming function stage from a callback or Function wrapper. Returns 1 on success, 0 on failure; a supplied wrapper transfers ownership on success.

## Signature

```recurloop
Shell:Pipeline:add_function(Shell:Pipeline*, Shell:Function*) -> i64
Shell:Pipeline:add_function(Shell:Pipeline*, fn(u8*)->u8* abi sysv-amd64) -> i64
```


