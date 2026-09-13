# RecurLoop Host ABI isolation overlay

This overlay moves native-action resolution out of the language lexicon and into explicit host/kernel state.
It removes the final runtime dependency on `Language::setup()` for normal embedded-core startup, while leaving the compatibility builder available for clean core-image bootstrap.

Key changes:
- explicit `HostAbi` registry for native actions;
- runtime action registry stored outside the radix/lexicon;
- `--reset` resets language state while preserving/reinstalling kernel Host ABI;
- imported/embedded images resolve native actions through Host ABI rather than hidden lexicon phrases;
- translation-unit workers start from the owner's current language image instead of rebuilding the legacy language;
- setup routines expose action-registration separately from compatibility syntax construction.
