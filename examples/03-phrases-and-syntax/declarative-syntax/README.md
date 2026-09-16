# Declarative syntax

This example family demonstrates the high-level `syntax` facility. A declaration is compiled into an ordinary rewritable phrase with a serializable pattern payload; it is therefore usable both at top level and while `fn` source is expanded.

Start with the small smoke example:

```bash
build/Release/bin/recurloop \
  --file examples/03-phrases-and-syntax/declarative-syntax/main.rl
```

The comprehensive showcase is intentionally verbose and executable:

```bash
build/Release/bin/recurloop \
  --file examples/03-phrases-and-syntax/declarative-syntax/showcase.rl
```

It covers:

- `syntax name ... => ...` rewrites;
- `<condition:expr>` and other expression captures;
- `<body:block>` plus `${body.body}`;
- `<name:id>`, `<value:number>`, `<value:string>`, `<value:token>`, and `<value:rest>`;
- optional groups `[ ... ]`;
- choice groups `(left | right)`;
- implicit layout plus `<space:required>`, `<space:none>`, `<line:newline>`, and `<whitespaces:ignore>`;
- `as <phrase>` semantic reuse;
- `syntax extend` with prototype fallback;
- `syntax replace` without fallback;
- `action fn` and `context:syntax:capture*` as the escape hatch;
- use at top level and inside compiled functions.

## Core forms

A source rewrite:

```rl
syntax unless <condition:expr> <body:block> => if (!(${condition})) ${body}
```

A semantic alias with a different spelling:

```rl
syntax when "(" <condition:expr> ")" <body:block> as <if>
```

Extend an existing construct while preserving its previous grammar as fallback:

```rl
syntax extend if "(" <condition:expr> ")" <body:block> as <if>
```

Replace its accepted grammar deliberately:

```rl
syntax replace if "(" <condition:expr> ")" <body:block> as <if>
```

For custom behavior, use an action only after the declarative matcher has done the structural parsing:

```rl
syntax literal <value:number> action fn (state:Context*, called:Phrase*) -> void {
    context:syntax:emit(state, context:syntax:capture(state, "value"))
}
```

## Engine-image round trip

The syntax phrase, pattern payload and phrase relationships are part of the engine image:

```bash
rm -f /tmp/recurloop-declarative-syntax.rli

build/Release/bin/recurloop \
  --file examples/03-phrases-and-syntax/declarative-syntax/roundtrip.rl

build/Release/bin/recurloop \
  --import /tmp/recurloop-declarative-syntax.rli \
  --file examples/03-phrases-and-syntax/declarative-syntax/after-import.rl
```

The second command tests both a custom `unless` rewrite and an extended `if` after deserialization.

## Design rule

Prefer, in order:

1. a declarative rewrite (`=>`) when the construct is syntactic sugar;
2. `as <phrase>` when only spelling/grammar changes and existing semantics can be reused;
3. `syntax extend` when a new form should coexist with the previous one;
4. `syntax replace` when the previous grammar must no longer match;
5. `action fn` only when a rewrite or semantic alias cannot express the behavior.

The low-level `context:syntax:*` cursor/emission API remains available, but ordinary language extensions should not have to manually scan source bytes.
