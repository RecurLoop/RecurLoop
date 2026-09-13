# Source-core parity map

`make core-parity` compares the compatibility language with a fresh
`core.rli` started through `--language-image`.

Current green surface:

| Area | Compatibility reference | Source-core reference |
| --- | --- | --- |
| functions / recursion | real `01-getting-started/functions-and-recursion` example | `parity/functions/core.rl` |
| ordinary control flow | real `01-getting-started/values-and-control-flow` example | `parity/control-flow/core.rl` |
| records / methods | real `01-getting-started/records-and-methods` example | `parity/records/core.rl` |
| defer + null propagation | real `01-getting-started/lifetime-and-null` example | `parity/lifetime-null/core.rl` |
| defer ordering | focused legacy fixture | `parity/defer/core.rl` |
| function values | focused legacy fixture | `parity/function-values/core.rl` |
| null / pointer expressions | focused legacy fixture | `parity/null-pointers/core.rl` |
| native extern interop | focused legacy fixture | `parity/extern-interop/core.rl` |

Known gaps are deliberately not marked green. In particular, the current
source-core path does not yet claim full parity for floating-point functions,
lexical namespace lookup/overload behavior, the complete phrase-extension
surface, debugger/assembler/emit commands, or every `02-functions` example.

The parity suite compares exit status, stdout, and stderr. A new area should be
added here only when both paths are semantically equivalent and the source-core
path does not fall back to `Language::setup()`.
