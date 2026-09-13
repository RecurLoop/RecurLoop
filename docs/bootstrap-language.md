# Bootstrap language boundary

RecurLoop has two distinct host language surfaces during the migration.

## Compatibility language

`Language::setup()` installs the historical C++ language. It remains the default
while source libraries are reaching feature parity.

## Fixed bootstrap language

`BootstrapLanguage::setup()` installs only the implementation surface required
to build or restore source-defined language images. It is selected with
`--bootstrap` and is also the base used by `--language-image`.

The bootstrap is intentionally not the RecurLoop user language. Its current
host-provided surface is limited to:

- typed native declarations needed by the seed (`link`, `extern`, primitive and
  pointer/function types);
- compiled implementation functions and their local expression/control-flow
  syntax;
- bootstrap bindings (`let`, `phrase`) and phrase references;
- `include` and engine image operations;
- Context API types and native functions.

Ordinary user-language roots such as `record`, top-level `if`, `print`, `emit`
and debugger commands are not bootstrap roots. The source libraries grow the
language from `proc` and `form`, with `shape` being the first source-defined
form.

The boundary is executable:

```sh
make bootstrap-contract
```

The contract test proves that the seed can grow syntax while representative
compatibility-only roots remain unavailable under `--bootstrap`.

## Migration rule

A compatibility subsystem may be deleted from C++ only after all of these are
true:

1. the equivalent source-library behavior exists;
2. `make core-parity` covers the behavior;
3. the complete unit/feature test suite stays green;
4. `make examples` stays green.

Shared implementation helpers can remain temporarily behind the bootstrap ABI.
They are not considered migrated merely because a source spelling exists.
