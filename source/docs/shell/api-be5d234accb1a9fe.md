Runs a pipeline synchronously and returns owned stdout and exit code, or null on failure. Release with Capture:destroy; the caller retains the pipeline.

## Signature

```recurloop
Shell:capture_pipeline(Shell:Pipeline*) -> Shell:Capture*
```


