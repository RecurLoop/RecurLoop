// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:foreign_functions = [
    id = phrase { payload = "foreign-functions" }
    title = phrase { payload = "Foreign functions" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "200" }
    body = phrase {
        payload = "An external declaration describes the native function you intend to call. RecurLoop uses that contract to pass arguments and interpret the result.

## Declare and link an external function

`extern` introduces a typed symbol contract. Built-in conventions include
`sysv-amd64`, `microsoft-x64`, `cdecl-x86`, `stdcall-x86`, and `fastcall-x86`.
Source can also define calling conventions.

```recurloop
link shared \"c\"
extern malloc(size:u64) -> u8* abi sysv-amd64
extern free(pointer:u8*) -> void abi sysv-amd64
```

## Reuse compatible declarations

Repeating an identical external declaration reuses the existing import,
including imports supplied by an engine image. The source name, native symbol,
parameter and result types, variadic flag, and calling convention must match.
A conflicting declaration or an external declaration over a function definition
is rejected."
    }
]
