```recurloop
directory path_expression { ... }
```

Runs a source block in the selected working directory, then restores the previous directory.

**Example**

```recurloop
directory "/tmp" { run pwd }
```


