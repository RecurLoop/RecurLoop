```recurloop
target name { ... }
target name depends [dependency, ...] { ... }
target name debug executable "path" { ... }
target name debug source "path.rl" { ... }
```

Declares a deferred project target. Dependencies run first; the body runs when the target is selected. The `depends [dependency, ...]` clause is optional and goes before `debug`.

**Example**

```recurloop
target build { include "build.rl" }
target debug depends [build] debug executable "./app" {}
```

## Syntax

```recurloop
<name:raw> [depends "[" <dependencies:raw> "]"] [debug (executable <executable:string> | source <program:string>)] <body:block>
```


