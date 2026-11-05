```recurloop
environment name_expression { ... }
```

Temporarily exports a RecurLoop runtime binding as an environment variable. The header evaluates to the binding name; the previous environment is restored on exit.

**Example**

```recurloop
var GREETING = "hello"
environment "GREETING" { run printenv GREETING }
```


