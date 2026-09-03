// Phrase-driven source debugger.
//
// Run from the repository root:
//   build/Debug/bin/recurloop --file examples/07-workflows/source-debugger/debugger.rl
//
// At the `debug>` prompt commands are themselves RecurLoop phrases. The
// `debug:` prefix is optional in the prompt. A useful tour is:
//   where
//   eval counter
//   delete 1
//   step
//   where
//   eval counter
//   continue

debug:trace on
debug:break phrase "print"
debug:run "target.rl"
