Releases a current-scope strong reference, destroying the payload when the last reference is gone. Returns 1 on success, 0 when no reference can be released.

## Signature

```recurloop
LanguageKit:Lifetime:release(Context*, u8*) -> i64
```


