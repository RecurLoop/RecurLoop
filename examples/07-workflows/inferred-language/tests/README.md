# Inferred-language tests

- `lazy-specialization`: one source function materializes independent integer
  and text bodies lazily and reuses the integer specialization.
- `control-flow`: inferred integer functions with locals and branching.
- `recursion`: one recursive call family reuses a single in-progress/ready signature specialization.
- `shared-interop`: ordinary RecurLoop values and LanguageKit call chaining.
- `selectors`: one-shot `infer` selection and dynamically scoped `infer {}`
  preference blocks without a separate lexicon.
- `phrase-visibility`: functions, parameters and grammar entries are visible as
  phrases in the shared RecurLoop lexicon.
