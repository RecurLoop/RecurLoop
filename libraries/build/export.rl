// Build helper shared by source-defined libraries.
//
// Usage:
//   recurloop [--import base.rli] --file path/to/library.rl -- output.rli
//
// The RecurLoop process argument cursor is part of the Host ABI. While the
// current source file is executing it points at the still-unconsumed `--`.
// Consume the separator and exactly one output path so Source does not try to
// open either token as another input file after the library has been exported.
let __recurloop_export_library = phrase {
    type = <phrase-types:elaborate>
    serializable = false
    action = fn (state:Context*, called:Phrase*) -> void {
        var index = state.exec.args.index
        if index >= state.exec.args.count {
            context:diagnostic:error(state, "library build requires: -- <output.rli>")
            return
        }

        let separator = state.exec.args.values[index]
        if !separator || strcmp(separator, "--") != 0 {
            context:diagnostic:error(state, "library output path must follow --")
            return
        }

        index += 1
        if index >= state.exec.args.count {
            context:diagnostic:error(state, "library output path is missing after --")
            return
        }
        if index + 1 != state.exec.args.count {
            context:diagnostic:error(state, "library build accepts exactly one output path after --")
            return
        }

        let output = state.exec.args.values[index]
        state.exec.args.index = state.exec.args.count
        context:engine:export(state, output)
    }
}
