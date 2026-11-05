Allocates managed storage in the current scope with a cleanup callback and userdata. Returns null on failure; release through Lifetime helpers rather than free.

## Signature

```recurloop
LanguageKit:Lifetime:alloc(Context*, i64, fn(Context*,u8*,i64)->void abi sysv-amd64, i64) -> u8*
```


