# RecurLoop autonomy migration

Status after this overlay: **Stage 7A COMPLETE. Stage 8 is NEXT.**

Stage 7 is intentionally split. Stage 7A establishes real source-owned compiled
actions and a monotonic host-action budget. Stage 7B (migration of the remaining
compiler/parser action implementations) is blocked on Stage 8 because those
implementations currently depend on C++-only working collections/parser frames.
After Stage 8, return to Stage 7B before starting Stage 9.

This file is temporary migration state for an AI agent. Update it after every autonomy overlay. The final autonomy overlay must delete `todo.md`.

## 0. Non-negotiable execution model

RecurLoop is a compiler, not an interpreter for ordinary function runtime.

Inside a compiled `fn`:

```text
source
  -> FunctionsParser / semantic compilation
  -> Statement / Expression representation
  -> native generator or LLVM backend
  -> machine code
  -> runtime execution later
```

Ordinary function-local `if`, `while`, blocks, assignments, locals and calls must execute in generated code. They must not automatically touch `Context`, `context.lexicon`, compiler registries or lexicon checkpoints at runtime.

A compiled program may manipulate `Context`/`Phrase`/lexicon only when it explicitly calls an API that does so. That is intentional metaprogramming/compiler interaction, not normal block semantics.

Do not introduce lexicon checkpoint/restore on runtime entry/exit of compiled function blocks.

## 1. Fixed target architecture

There is one persistent/serializable semantic graph for the language and compiler: **`context.lexicon`**.

It is intended to contain or reference:

```text
language grammar / phrases
compiler registry
  types
  functions
  modules
  calling conventions
  settings
  link inputs
compiled RecurLoop actions/modules
compile-time/elaboration values
compiler-defined collections and object graphs
other semantic state required to reconstruct core.rli
```

Do not add a second generic registry/store alongside the lexicon. The existing radix/lexicon is the canonical indexed semantic store.

This does NOT mean all runtime program memory belongs in the lexicon. Runtime function locals, stack slots, heap objects, large numeric buffers etc. remain ordinary generated-program memory unless a program explicitly stores them in/through lexicon objects.

For compiler working data that needs sequential access, `.rl` may define structures such as chunked deque/sequence objects backed by arena allocations. The lexicon can index/name/reference them; it does not need to encode every byte as a separate phrase.

## 2. Final host/core boundary

Target production executable:

```text
final recurloop
├── radix/lexicon memory kernel
├── generic image load / save / relocate / merge primitives
├── raw memory allocation and executable-memory primitives
├── process / filesystem / native-call boundary
├── generic compiled-action invocation/JIT boundary
├── LLVM backend behind a language-neutral backend ABI
└── embedded core.rli
    ├── language grammar
    ├── standard actions implemented in RecurLoop where possible
    ├── compiler registry schema
    ├── type-system semantics
    ├── compiler algorithms
    ├── compiler collections/work structures
    ├── modules/settings/link semantics
    └── lowering to the backend ABI
```

LLVM itself may remain C++. The goal is to remove RecurLoop front-end/language semantics from the LLVM implementation, not to rewrite LLVM APIs in `.rl`.

The host must not gain new language-specific registries or new hard-coded compiler schema after freeze.

## 3. Lexicon invariants

1. Keys may contain arbitrary bits. Payloads may contain arbitrary bytes.
2. The radix is append/version oriented. Shadowing creates a newer record; rollback is reverse chronological.
3. Compiler/elaboration semantic state that must be rollback-safe should prefer append/shadow over mutation of a record that predates the checkpoint.
4. A radix checkpoint is a transaction over allocations after one watermark. It is only used where compile-time/elaboration semantics intentionally require rollback.
5. `permanent` protects language-level replacement/mutation; it does not make an allocation survive a radix rollback.
6. If selected semantic state created after a compile-time checkpoint must survive that rollback, it requires explicit **promotion/escape**: capture selected relocatable state, rollback, then merge/replay selected state into the parent state.
7. `commit()` of a lexicon transaction keeps the entire post-checkpoint allocation range. It is not selective promotion.
8. Process-local caches/resources may live outside the lexicon only when they are non-semantic/rebuildable or inherently process/backend resources.
9. No mandatory compaction is required for normal compiler transactions. LIFO rollback is the intended temporary-lifetime mechanism. Long-lived REPL/daemon compaction can remain an optional future operational feature.

## 4. Important distinction: three kinds of scope/state

### A. Compiled function runtime scope

Examples: a local block inside `fn`, runtime `if`, runtime `while`, local variables.

Implementation: generated native/LLVM code and runtime memory.

**Never automatically lexicon-checkpoint this scope.**

### B. Compile-time/elaboration value scope

`Blocks::execute(..., scoped=true)` currently uses `ValueScope`, which calls `context.values().pushScope()/popScope()`. These values are stored using lexicon phrases, but their scope semantics are prototype/active-scope based, not whole-lexicon rollback.

Do not replace `ValueScope` wholesale with `LexiconTransaction` unless a later stage explicitly defines and tests the desired compile-time semantics. In particular, this mechanism is not evidence that runtime function blocks should checkpoint the lexicon.

### C. Explicit compiler/language transaction

Existing examples include language `scope.enter`, translation-unit temporary state and assembler/compiler sessions that explicitly checkpoint the radix.

These are the places where the common transaction abstraction can eventually replace hand-written checkpoint plumbing after their semantics are audited.

## Stage 0 — architecture lock + transaction primitive — COMPLETE

Implemented:

- `include/recurloop/LexiconTransaction.hpp`
  - one RAII watermark over the existing shared lexicon;
  - rollback by default;
  - exception-safe;
  - explicit whole-range `commit()`.
- `tests/unit/recurloop/language/lexicon_transaction_test.cpp`
  - proves a normal language phrase and compiler-registry setting share the same radix transaction;
  - proves exception rollback;
  - proves whole-transaction commit.

This stage intentionally changes no existing scope semantics.

## Stage 1 — semantic mutation and checkpoint audit — COMPLETE

Snapshot audited: `recurloop(20260914-103303)` plus corrected Stage 0.

Audit totals before the Stage-1 fixes:

```text
25 explicit Phrase::update(...) call sites
10 explicit lexicon checkpoint captures
14 explicit radix checkpoint restores
```

The audit also covered saved-phrase metadata setters (`setType`, `setPrototype`, `setSuccessor`, `setAction*`, serializable/permanent/rewritable flags) because `Phrase::save()` writes metadata in place for an already allocated phrase.

### 1.1 Semantic in-place mutations

#### Fixed in this stage

`compiler::LanguageState::bind()` previously rewrote an existing serialized `LanguageBinding` payload with `Phrase::update()`.

That is no longer allowed:

```text
same language binding     -> idempotent no-op
different language binding -> error; caller must create/version a phrase
```

Reason: rebinding a phrase that predates a radix checkpoint would otherwise survive rollback.

`contextSourceHook()` previously mutated the hidden `\0source-hook` marker's prototype in place. It now appends a new marker with the same key. The latest marker shadows the old one, so radix rollback naturally restores the previous hook.

#### Explicit mutation boundary; intentionally NOT made transactional yet

These APIs intentionally mutate an existing phrase identity in place:

```text
ContextApi::contextPhraseSet(...)
ContextApi::contextPhraseSetAction(...)
PhraseDefinition::mutate(...)
```

They are explicit metaprogramming APIs. A plain radix allocation checkpoint cannot undo their writes to a phrase that existed before the checkpoint.

**Ongoing rule:** do not place arbitrary execution that may call these mutation APIs inside a full lexicon rollback transaction and assume restore() will undo them. A future versioned mutation/promotion mechanism must be used when such behavior is required.

This is not ordinary compiled-function runtime. These APIs are reached only when code explicitly manipulates compiler/language objects.

#### Safe initialization-only metadata writes

The following saved-phrase setters are used while constructing fresh phrases/core state before those objects become transaction-visible:

```text
LanguageActions::setup_phrase_types()
FunctionsParser::bindSyntaxPrototypes() during C++ seed/bootstrap setup
Recurloop empty-root initialization
CoreDefinition materialization
EngineImage import/merge relocation of newly created destination phrases
ContextApi phrase-definition finalization of a newly created phrase
```

They do not modify a pre-checkpoint semantic object during a rollback-capable transaction.

#### Process/backend caches

The following in-place metadata writes are deliberately process-local/rebuildable and are not serialized semantic identity:

```text
Functions::invokeBoundAction()       -> ActionBinding::entry JIT cache
Assembler deferred/native action     -> ActionBinding::entry native/JIT cache
```

Engine-image serialization intentionally omits/reconstructs these entry addresses. They may remain in-place.

#### Assembler/session payload updates

All remaining `Phrase::update()` calls are assembler/compiler-session state, not persistent compiler registry schema.

Ownership:

```text
AssemblerSessionData
  created after assembler_begin lexiconCheckpoint
  mutated until assembler_end
  entire session range is discarded by assembler_end restore

CompiledScopeSessionData
  created after action_let_scope lexiconCheckpoint
  used while generating one compiled scope
  range is discarded before finalizing the generated definition

instruction-local operand phrases
  created after instructionLexiconCheckpoint
  discarded when instruction encoding finishes or is abandoned

assembler labels / relocation counters / invocation counters
  allocated inside the owning assembler session
  may be mutated in-place because the label/session itself is newer than the
  outer assembler checkpoint; the whole assembler transaction removes it

native-output directive
  explicit short-lived command/session state created by set_native_output()
  then updated while consuming exactly that output request
  it is not compiler registry state and is not assumed to be reversible by an
  unrelated outer checkpoint
```

Important nested-checkpoint detail: `AssemblerSessionData` predates an instruction-local checkpoint and is intentionally mutated across that nested checkpoint. Instruction error/discard paths explicitly reset its instruction fields after restoring instruction-local allocations. Do not blindly replace those nested checkpoints with an RAII rollback that assumes every session field is versioned.

### 1.2 Existing lexicon checkpoint inventory

#### `ContextApi::definePhrase()`

Purpose: exception safety for one phrase definition through the C ABI.

```text
checkpoint
  allocate inline action/phrase metadata/new phrase
success -> keep allocation
failure -> restore checkpoint
```

Expected writes are new allocations only. No existing phrase mutation is required.

#### `TranslationUnitRegistry::start()` worker checkpoint

Purpose: establish the base-image watermark in an isolated worker context and encode only the translation-unit delta with `EngineImage::encode(context, checkpoint)`.

It is a capture boundary, not a rollback scope. Worker lifetime owns the temporary context.

#### `TranslationUnitRegistry::merge()` checkpoint

Purpose: strong exception safety while merging a translation-unit image into the owner lexicon.

On failure, all allocations made by the merge are discarded. Merge materializes/version-shadows destination phrases; it does not intentionally mutate owner phrases that predate the checkpoint.

#### `LanguageActions` reference/dictionary whitespace checkpoints

Purpose: install temporary parsing phrases while collecting whitespace/reference text.

Paired state:

```text
lexicon watermark
workspace.key bit watermark where discard semantics require it
```

Temporary grammar phrases are created after the checkpoint and removed on apply/discard/end.

#### `LanguageActions::action_scope`

Purpose: explicit language/elaboration transaction for the old `scope.enter`-style grammar.

It stores one lexicon watermark in the temporary closing phrase and restores it on `}`. This is compile-time/language state, not runtime scope of a compiled `fn`.

Stage 2 formalized this transaction API without broadening its semantics. Any selective escape from this scope belongs to Stage 3 promotion.

#### assembler outer-session checkpoint

Captured in `action_assembler_begin()` as `AssemblerSessionData::lexiconCheckpoint`.

Purpose: own all assembler parser/session labels, relocations and other temporary phrases for one assembler block. `action_assembler_end()` restores it after second-pass/link preparation.

Parallel non-lexicon state includes `workspace.code` and `workspace.key` starting positions recorded in session data and restored/consumed by assembler helpers as appropriate.

#### assembler instruction-local checkpoint

Captured when an instruction begins.

Purpose: temporary operand phrases only. They are removed before relocation records are appended, so relocation records survive until the assembler block second pass.

The assembler session object itself predates this nested checkpoint and is intentionally maintained/reset explicitly.

#### compiled-scope checkpoint

Captured in `action_let_scope()` as `CompiledScopeSessionData::lexiconCheckpoint` with code/key/staging positions.

Purpose: temporary compiler phrases used to generate one compiled native scope. Generated code/module data is finalized separately; lexicon session phrases are then discarded.

### 1.3 Runtime separation verified

No ordinary compiled function block was coupled to `LexiconTransaction`.

`fn` bodies continue through:

```text
FunctionsParser -> Statement/Expression -> native generator / LLVM -> runtime
```

Runtime `if`, `while`, locals, assignments and calls do not implicitly checkpoint or mutate `context.lexicon`.

### Stage-1 code/tests added

- `LanguageState::bind()` can no longer silently rewrite an existing language binding.
- `contextSourceHook()` now versions its hidden marker by radix shadowing.
- explicit in-place metaprogramming APIs are documented at their mutation boundary.
- `lexicon_transaction_test.cpp` checks that an existing binding is idempotent and rejects an attempted different in-place binding.

### Stage-1 completion result

The current automatic/internal compiler state is classified with checkpoint ownership. The only intentionally rollback-unsafe semantic mutation surface is the explicit phrase-mutation metaprogramming API listed above; later stages must not accidentally treat it as rollback-safe.

## Stage 2 — formalize compile-time transaction semantics — COMPLETE

Goal achieved: existing explicit compiler/elaboration rollback owners now use one named lexicon-transaction abstraction where their semantics are a plain post-watermark allocation transaction. No compiled-function runtime scope semantics were changed.

### 2.1 `LexiconTransaction` is now the canonical transaction primitive

`include/recurloop/LexiconTransaction.hpp` now provides both forms required by the existing parser/compiler architecture:

```text
RAII lifetime in one C++ call:
  LexiconTransaction transaction(lexicon)
  ...
  transaction.commit()       // keep entire post-watermark range
  // otherwise destructor rolls back

callback-spanning lifetime:
  watermark = LexiconTransaction::capture(lexicon)
  ... later callback ...
  LexiconTransaction::restore(lexicon, watermark)
```

The callback form exists because several language actions store the watermark in a temporary lexicon phrase and finish in a later parser callback. It is not a second transaction stack; it is the same radix address watermark.

`commit()` is still whole-range commit only. It is not selective promotion.

### 2.2 Converted owners

#### `ContextApi::definePhrase()`

Converted from manual:

```text
capture address
try define phrase
catch -> restore address
```

to an RAII `LexiconTransaction`.

Success explicitly commits. Every early return or exception automatically restores post-watermark allocations. The existing explicit `contextPhraseSet*` mutation boundary is unchanged: in-place writes to pre-existing phrase identities are still not rollback-safe.

#### `TranslationUnitRegistry::merge()`

Converted to RAII `LexiconTransaction` around owner-image merge.

Both direct image merge and compiled translation-unit merge commit only after `EngineImage::merge()` succeeds. Any exception from descriptor compilation/result retrieval/image merge rolls back allocations made in the owner lexicon.

The worker-side checkpoint in `TranslationUnitRegistry::start()` is deliberately unchanged because it is an **image-delta capture boundary**, not a rollback transaction.

#### callback-spanning language transactions

The following existing mechanisms now use `LexiconTransaction::capture/restore` instead of constructing raw `radix::Checkpoint` objects themselves:

```text
reference whitespace temporary grammar
reference whitespace discard/apply/end
dictionary whitespace temporary grammar
dictionary whitespace discard/apply/end
language `scope.enter` / closing `}` rollback
```

Their language semantics are unchanged. Stage 2 only gives them one transaction API and one explicit meaning: restore all lexicon allocations after the stored watermark.

### 2.3 Deliberately NOT converted

#### `Blocks::execute(..., scoped=true)` / `ValueScope`

Still uses `context.values().pushScope()/popScope()` only. This is compile-time/elaboration value-scope semantics, not proven to be a whole-lexicon rollback transaction. Do not change it merely because the source syntax contains braces.

#### assembler outer/instruction checkpoints

Still use their explicit session watermarks and reset logic. Stage 1 proved that `AssemblerSessionData` may predate a nested instruction checkpoint and is intentionally mutated across it. Replacing this mechanically with RAII would hide the required paired workspace/session restoration.

#### compiled native-scope checkpoint

Still owned by `CompiledScopeSessionData` together with code/key/staging positions. It is a compiler-generation session boundary, not ordinary runtime block scope.

#### translation-unit worker delta checkpoint

Still a raw capture address because `EngineImage::encode(context, checkpoint)` needs the address to encode only the worker delta; no rollback occurs there.

### 2.4 Stage-2 tests

`lexicon_transaction_test.cpp` now additionally requires:

- nested transactions restore the byte-identical parent semantic image;
- after the outer transaction also rolls back, the original image is byte-identical;
- a stored watermark can be captured in one logical callback and restored later using `LexiconTransaction::restore()`;
- compiler-registry shadowing performed in a nested transaction disappears together with normal language phrases.

The existing Stage-0/1 tests remain and continue to check exception rollback, whole-range commit, compiler-registry sharing, language-binding immutability and source-hook shadow rollback.

### 2.5 Stage-2 invariant

After this stage, there are three intentionally distinct mechanisms and they must not be conflated:

```text
LexiconTransaction
  explicit semantic compiler/elaboration allocation transaction

ValueScope
  compile-time value visibility/prototype scope

compiled function scope
  generated native/LLVM runtime semantics
```

Stage 3 adds selective semantic escape across `LexiconTransaction` while preserving this separation.

## Stage 3 — generic semantic promotion/escape — COMPLETE

Implemented selective semantic escape for explicit `LexiconTransaction` scopes.

### 3.1 API and semantics

`LexiconTransaction::promote(context, roots)` is the selective counterpart to `commit()`:

```text
transaction checkpoint C
  temporary state A
  selected semantic graph P
  temporary state B
promote(P)
  capture P + visible serializable descendants + relocations
  reject dependencies on unselected state created after C
  rollback exactly to C
  replay only P into the restored parent lexicon
```

`commit()` still means keep the entire post-checkpoint allocation range. Do not use it for selective escape.

Promotion is compile-time/compiler semantic machinery only. It does not participate in ordinary generated-function runtime scopes.

### 3.2 Dependency rules

A promoted phrase may reference:

```text
another promoted phrase
or
any phrase whose address predates the transaction checkpoint
```

A promoted phrase may NOT reference an unselected phrase created after the checkpoint. Such a dependency would become dangling after rollback and is rejected before rollback occurs.

A selected root may be nested under another selected phrase. If its dictionary owner was created after the checkpoint and is not selected, promotion is rejected.

Promotion always re-appends the selected records after rollback; it does not reuse an existing same-key phrase. This preserves the lexicon's append/shadow version semantics.

### 3.3 Failure behavior

Validation happens before the original transaction is destroyed. If validation fails, the transaction remains active and the caller may rollback normally.

After the parent rollback, replay itself is protected by a second watermark. If replay fails, all partial replay allocations are removed and the parent state remains restored.

### 3.4 Tests

`lexicon_transaction_test.cpp` now requires:

- selected dictionary/subtree survives while unrelated transaction state disappears;
- a payload `PhraseReference` inside the promoted graph is relocated to the replayed child;
- dependencies on unselected post-checkpoint state are rejected;
- the transaction becomes inactive only after successful selective promotion.

## Stage 4 — image-safe arbitrary `.rl` objects/references — COMPLETE

Implemented generic payload-layout metadata in the lexicon. Future `.rl` object schemas can declare image semantics for payload fields without adding a new `EngineImage.cpp` hard-coded struct case.

### 4.1 Layout model

`EngineImage::declarePayloadField(context, schema, offset, kind)` declares a field for phrases whose **direct prototype is `schema`**.

Supported generic field kinds:

```text
PhraseReference
  payload contains a Size phrase address
  EngineImage converts it to/from a relocatable phrase id

NativePointer
  payload contains a process pointer
  zero is allowed
  non-zero explicitly makes image serialization fail
```

Plain bytes/scalars need no layout declaration.

The layout metadata is itself stored in `context.lexicon` under the hidden kernel namespace:

```text
\0image-layouts
  layout entry --successor--> schema phrase
    field keyed by binary offset -> field kind
```

The schema relation uses normal phrase metadata and therefore relocates through `.rli` without an address-stable registry key. The binary child key is only an opaque unique descriptor key; lookup is by the relocated schema relation.

No new `.rli` binary format/version was required: generic phrase references use the existing `RelocationKind::Phrase` encoding.

### 4.2 `.rl` / Host ABI access

The source-built core declares two generic host primitives:

```text
context:phrase:image:reference(Context*, schema, offset) -> schema
context:phrase:image:native(Context*, schema, offset) -> schema
```

They only declare image ownership/relocation semantics. They do not define compiler registry schema or a second store.

These primitives are intentionally generic kernel/image facilities and may remain in the final host primitive whitelist.

### 4.3 Engine image behavior

During capture, `EngineImage` now:

1. loads generic payload layouts from the lexicon;
2. discovers `PhraseReference` targets so referenced shadowed phrases remain reachable;
3. emits standard phrase relocations for those offsets;
4. zeroes serialized process addresses as required by relocation;
5. rejects a non-zero declared `NativePointer` instead of accidentally persisting a process-local address.

The metadata survives image decode, so a subsequent encode still knows the layout without C++ re-registering it.

The same generic relocation metadata is consumed by Stage-3 promotion because promotion captures through the engine-image relocation model before rollback.

### 4.4 Tests / verification

`engine_image_test.cpp` now requires:

- a schema-defined generic phrase reference round-trips through `.rli` and points at the relocated target;
- the schema/layout metadata itself survives decode and is usable by subsequent capture/promotion;
- a declared non-zero native pointer is rejected by image serialization.

Standalone Stage-3/4 harnesses also verified selective replay, internal reference relocation and rejected unselected transaction dependencies.

## Stage 5 — change bootstrap proof from parity to self-hosting — COMPLETE

The bootstrap parity proof has been removed. A clean build now uses a genuinely
smaller stage-0 seed whose only language job is to enter the semantic
`engine define { ... }` block in `core.rl`.

### 5.1 Minimal seed

The old full `bootstrap::Language::setup()` implementation was removed.
`bootstrap::SeedLanguage::setup()` now creates only:

```text
root / phrase-type kernel
canonical `{` and `}` grammar markers
root whitespace
`engine` dictionary whitespace
`engine define`
```

The checked-in `core.rl` begins directly with `engine define { ... }`, so the
seed does not need comments, expressions, `let`, functions, compiler registry,
assembler syntax, control flow or any ordinary standard-language phrase.

Current clean-build image sizes in the Stage-5 validation build:

```text
seed.rli  = 2,106 bytes
core.rli  = 283,167 bytes
```

Do not treat the exact byte counts as ABI constants; the invariant is that the
seed is a distinct, strictly smaller image.

### 5.2 Exact build-image restore

Normal `EngineImage::decode()` retains its compatibility behavior of restoring
an image and then ensuring normal compiler/value defaults.

The private core build runner now uses `EngineImage::decodeExact()` instead.
Exact restore reconstructs only the serialized image graph plus process-local
action bindings and lookup/staging/reference state. It does **not** inject
`LanguageState::setup()` or `Values::setup()` state before `core.rl` runs.

This is required for the Stage-5 proof: `seed.rli` must not receive a hidden
compiler registry from C++ before `engine define` replaces the seed lexicon.
`CoreDefinition::apply()` is responsible for materializing the full source core,
including compiler state, and then initializes the value/compiler state declared
by that source graph.

Do not replace `decodeExact()` in the seed/core runner with normal production
`initializeEmbedded()`; the latter intentionally assumes an already complete
core image and immediately binds ContextAPI declarations.

### 5.3 Build pipeline

The private build targets are now:

```text
RecurloopSeedLib
RecurloopSeedBuilder -> seed.rli
RecurloopCoreRunner  -> core.rli / core-2.rli
```

The clean-build proof is:

```text
minimal C++ seed
    -> seed.rli
seed.rli + core.rl
    -> core.rli
core.rli + core.rl
    -> core-2.rli
require core.rli == core-2.rli byte-for-byte
embed core.rli
```

There is deliberately no `seed.rli == core.rli` comparison.

`cmake/ValidateSeedImage.cmake` additionally fails the build if:

```text
seed.rli == core.rli
or
size(seed.rli) >= size(core.rli)
```

This prevents accidental regression to the old parity/bootstrap model.
`cmake/ValidateCoreSource.cmake` still rejects numeric-id/image-dump style core
source.

### 5.4 Production boundary

`RecurloopSeedLib` is a private build-time dependency only. The production
executable remains:

```text
Recurloop -> RecurloopRuntimeLib -> RecurloopLib
```

and embeds only the self-hosted `core.rli`. It does not link the seed library or
seed language.

### 5.5 Stage-5 verification

The Stage-5 validation build proved:

```text
seed.rli + core.rl -> core.rli
core.rli + core.rl -> core-2.rli
core.rli == core-2.rli
```

and `libraries/recurloop/test-core.sh` still passes:

```text
embedded == reset+import
reset leaves only the host kernel
recurloop --file core.rl reproduces core.rli
reset+import core.rli + core.rl reproduces core.rli
```

### 5.6 What Stage 5 does NOT claim

`CoreDefinition::apply()` is still implemented in C++ and still knows how to
materialize the compiler declarations from `core/compiler.rl`. Production
`LanguageState`/`TypeRegistry` still know hidden compiler-registry names and
layouts. Standard phrases still predominantly bind `action host "..."`.

Those are Stage 6 and Stage 7. Do not call Stage 5 full self-hosting of compiler
semantics; it is the correct **self-reproducing core bootstrap boundary** that
allows those later migrations without requiring the seed to duplicate the final
language.

## Stage 6 — source-own the compiler registry schema — COMPLETE

### Goal

Physical compiler data already lived in the shared lexicon, but production C++
still owned its physical topology: hidden root/key strings, settings/counter slot
keys and ABI-kind initialization. Stage 6 removes that physical schema knowledge
from production `LanguageState`/`TypeRegistry`.

This stage deliberately does **not** claim that compiler algorithms are
self-hosted. Function/type/module lookup logic and payload codecs remain C++
algorithms until Stage 7/8. The completed invariant is narrower and testable:

> `core/compiler.rl` owns the physical compiler-registry graph. Production C++
> addresses that graph only through stable semantic role tags serialized in the
> lexicon/image.

### Source-owned declarations

`libraries/recurloop/core/compiler.rl` now declares:

```text
language-root <source-chosen key>

registry calling-conventions <source-chosen key>
registry functions <source-chosen key>
registry function-sources <source-chosen key>
registry modules <source-chosen key>
registry settings <source-chosen key>
registry module-selections <source-chosen key>
registry link-objects <source-chosen key>
registry link-archives <source-chosen key>
registry link-paths <source-chosen key>
registry shared-libraries <source-chosen key>
registry types <source-chosen key>
registry type-ids <source-chosen key>
registry abi-kinds <source-chosen key>

slot type-next-id <source-chosen key> 1
slot automatic-modules <source-chosen key> true
slot embed-language <source-chosen key> true
slot selection-generation <source-chosen key> 0
slot link-sequence <source-chosen key> 0
slot link-generation <source-chosen key> 0
slot module-entry <source-chosen key>

abi-kind void void
abi-kind integer integer
abi-kind floating floating
abi-kind pointer pointer
abi-kind array aggregate
abi-kind structure aggregate
abi-kind function pointer
```

The strings following those semantic roles are data owned by source, not an ABI
contract with production C++.

### Stable semantic tags

`compiler/RegistrySchema` defines small image-safe metadata tags:

```text
Language
RegistryBinding { RegistryRole }
SlotBinding     { SlotRole }
```

`CoreDefinition` materializes the source-declared graph and writes these tags.
`LanguageState` and `TypeRegistry` locate registries/slots by role instead of by
physical path/key. Slot updates append/shadow the source-owned key, preserving
the shared lexicon transaction model.

The semantic role enums are intentionally still C++ at this stage because the
production compiler algorithms that consume them are still C++. Stage 7 moves
those semantic actions/algorithms toward `core.rli`; do not reintroduce physical
key knowledge as an intermediate shortcut.

### Engine image restore

Normal `EngineImage::decode()` no longer synthesizes compiler registry topology
by calling a C++ `LanguageState::setup()`. The topology is part of the
serialized/source-built core. Decode validates/locates the source-defined schema
instead. The minimal Stage-5 seed remains compiler-registry-free.

### Build-time ownership guard

`cmake/ValidateCompilerSchemaOwnership.cmake` is part of the core fixed-point
build. It fails if production `LanguageState.cpp` or `TypeSystem.cpp` spells any
of the source-owned physical registry/slot keys.

This guard is architectural, not stylistic: changing a physical key in
`core/compiler.rl` must not require a production C++ edit.

### Integration proof

`tests/feature/recurloop/language/compiler_schema_source_owned.cmake` copies the
source core, renames the physical registry and slot keys while leaving semantic
roles unchanged, then verifies:

```text
embedded core + renamed core.rl -> renamed core.rli
renamed core.rli + renamed core.rl -> renamed core-2.rli
renamed core.rli == renamed core-2.rli
renamed core.rli executes normal source correctly
```

A direct manual version of the same test was also used during Stage 6, including
renaming `functions`, `types`, module/link registries, counters/settings and ABI
registry keys; the result still reached a byte-for-byte fixed point and executed
`print 2 + 3 * 4` as `14`.

### Stage 6 non-goals

Do **not** interpret completion of Stage 6 as permission to delete all compiler
C++. The following are still expected to remain for now:

- typed function/type/module registry algorithms;
- compiler payload serialization/decoding;
- overload/linking/compiler working algorithms;
- standard `action host "..."` implementations;
- LLVM/native backend implementation.

Those are addressed by Stage 7 onward.

## Stage 7 — move standard semantic actions/compiler algorithms into core.rli

### Stage 7A — source-owned compiled action layer — COMPLETE

The core now has a real source-owned action binding layer in
`libraries/recurloop/core/actions.rl`. These are normal RecurLoop `fn`
implementations compiled while building `core.rli`; after image reload the target
phrases invoke them through the generic `fn.bound-action` mechanism. They are not
wrappers which dispatch to the old semantic C++ callbacks.

The first migrated batch is:

```text
language.ignore
language.ping
source.progress-byte
workspace.pass-byte
workspace.pass-cr
workspace.pass-lf
workspace.pass-tab
workspace.pass-vtab
hex.byte
```

`Core:ActionBindings` maps the bootstrap action identity to a carrier phrase whose
compiled implementation lives in the image. `context:actions:bind_root` is a
build-time generic binder: it does not know any migrated action names and only
replaces matching bootstrap action pointers with the already-compiled phrase
implementation. After binding, final target phrases contain `fn.bound-action` plus
the serialized implementation reference.

The small supporting Context primitives added for this first batch are mechanism,
not language semantics:

```text
context:actions:bind_root
context:io:write
context:workspace:key:append_byte
context:workspace:code:append_byte
```

The final image is audited by `cmake/ValidateSourceActions.cmake` against
`libraries/recurloop/core/host-actions.allow`. The audit has three hard rules:

1. migrated actions above may not occur as direct `action "..."` fields;
2. every remaining direct host action must be explicitly present in the reviewed
   allowlist;
3. stale allowlist entries are errors, so the budget only shrinks when actions are
   migrated.

At completion of Stage 7A the reviewed direct host-action budget is **210**. The
self-hosted `core.rli == core-2.rli` fixed point remains byte-for-byte, and
`debug ping` executes through the compiled source-owned implementation from the
embedded core image.

Compiler-internal source-action JIT is deliberately isolated from the user's
module-output policy. `LanguageState::composeInternalModule()` follows only
transitive RecurLoop module dependencies and ignores `module entry/include`,
exclusions, auto/manual mode and link inputs. This is required because an action
may first execute while parsing a function selected as the output entry before
that function's module exists. `source_owned_actions.cmake` is the regression
test for this boundary.

### Stage 7B — migrate remaining semantic actions/compiler algorithms — BLOCKED BY STAGE 8

Do not fake completion by replacing the remaining callbacks with `.rl` wrappers
that simply call the same C++ implementation. The remaining action groups are
mostly backed by C++-only compiler/parser working state:

```text
expressions.*
fn.*
typed.*
phrase.field.* / phrase.define
dictionary.* / reference.* / name interpolation
assembler.*
debugger.*
```

Some true boundary actions in those groups may ultimately remain host/backend
primitives, but normal parser/compiler algorithms must move to RecurLoop. To do
that without smuggling private C++ state behind helper calls, first provide the
compiler collections/work-memory layer from Stage 8. Then return here, migrate the
remaining expressible algorithms, delete their C++ callbacks/registrations, and
reduce `host-actions.allow` to the genuinely irreducible kernel/backend boundary.

Stage 7 final invariant remains:

> adding a parser action, language construct, compiler registry algorithm or
> normal compiler collection does not require production C++.

## Stage 8 — compiler collections/work memory in `.rl` — NEXT

Provide the collection primitives/implementations needed by the self-hosted compiler.

The shared lexicon is the canonical named/indexed semantic graph. Sequential data may use `.rl`-defined chunked deque/sequence structures backed by arena memory where appropriate.

Do not force large runtime-like buffers into one-phrase-per-element representation merely to satisfy the single-lexicon principle.

All data required to reproduce semantic compiler state/core images must have image-safe ownership/reference rules from Stage 4.

## Stage 9 — isolate LLVM behind a language-neutral backend ABI

Do not rewrite LLVM itself in RecurLoop just to remove C++.

Remove RecurLoop front-end/language knowledge from `LlvmBackend.cpp`. The self-hosted compiler should lower to a stable backend-neutral representation/API. The LLVM implementation consumes only backend types/modules/functions/blocks/instructions and target options, then emits/JITs code.

Target:

```text
core.rli compiler
  -> backend-neutral module/IR/API
  -> LLVM backend C++
  -> object/executable/JIT
```

A future backend should be addable without changing language semantics.

## Stage 10 — final freeze

Before declaring the host complete:

- clean build with LLVM ON;
- all unit tests;
- all feature tests;
- all examples/workflows;
- `core.rli == core-2.rli` self-hosting fixed point;
- negative fixed-point test: semantic modification of `core.rl` must affect/fail the expected core comparison;
- promotion/relocation tests;
- host-action whitelist audit;
- no production C++ compiler-registry schema knowledge;
- no semantic compiler state outside the lexicon except explicitly documented backend/process resources;
- ordinary compiled function runtime verified to execute without implicit Context/lexicon interaction;
- final architecture documentation updated;
- **delete `todo.md` in the final overlay.**

## Rules for the next AI agent

1. Read this entire file before editing.
2. Work on the first **unblocked** incomplete stage. Stage 7B is explicitly
   blocked by Stage 8; complete Stage 8 next, then resume Stage 7B before Stage 9.
3. Preserve the compiler execution model: runtime function blocks are generated code, not lexicon transactions.
4. Do not introduce a second generic semantic store/registry alongside `context.lexicon`.
5. Do not turn `Blocks::execute(scoped=true)` into a whole-lexicon transaction without an explicit semantic reason and tests.
6. Do not use `commit()` to fake selective promotion.
7. Do not mutate pre-checkpoint semantic records in-place if rollback is expected to restore them.
8. Preserve `EngineImage::source()` legacy round-trip support; it is distinct from semantic `core.rl`.
9. Do not weaken byte-for-byte self-hosting/fixed-point checks to make a build pass.
10. Keep LLVM as an external/backend boundary rather than porting LLVM internals to `.rl`.
11. Every stage must leave normal runtime/function/examples behavior green.
12. Update the status and completed-stage notes in this file after each overlay.
13. The final overlay deletes this file.
