Temporarily sets an environment variable and returns a guard, or null on failure. Restore and release with Shell:env_leave.

## Signature

```recurloop
Shell:env_enter(u8*, u8*) -> Shell:EnvGuard*
```


