// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:dependencies = [
    id = phrase { payload = "dependencies" }
    title = phrase { payload = "Dependencies" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "20" }
    body = phrase {
        payload = "## Resolve dependencies before target bodies

Put prerequisites in `depends [name, ...]`, before the body or a `debug` clause. Dependencies are target names, not shell commands or file paths.

```recurloop
import project
target assets { print \"prepare assets\" }
target validate depends [assets] { assert 2 + 2 == 4 }
target preview depends [assets] { print \"preview ready\" }
target all depends [validate, preview] { print \"all ready\" }
```

The shared `assets` target runs once when resolving `all`. A failed dependency prevents dependent bodies from running. A missing target or cyclic dependency is an error; do not use cycles as a mechanism for repeated execution.

## Separate definition from effects

Create values and phrases needed by multiple targets outside their bodies. Keep side effects inside the target that owns them. Declaring a target is safe during project discovery precisely because its body remains deferred. A target that writes a file should make that effect explicit in its own source and handle failures before returning success.

## Distinguish targets from file caches

Target execution is dependency-driven, not an automatic file timestamp cache. Do not assume that an unchanged input file causes a target to be skipped across separate runtime invocations."
    }
]
