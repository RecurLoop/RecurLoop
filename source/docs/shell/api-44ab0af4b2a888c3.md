Starts a pipeline, optionally capturing stdout. A single pipeline is asynchronous; conditional lists wait between pipelines. Returns null on failure; release with Invocation:destroy.

## Signature

```recurloop
Shell:Invocation:start(Shell:Pipeline*, i64) -> Shell:Invocation*
```


