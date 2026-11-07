// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:libraries = [
    id = phrase { payload = "libraries" }
    title = phrase { payload = "Libraries" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "180" }
    body = phrase {
        payload = "Libraries add reusable names and language behavior to the active environment. Start with a standard library whose job matches your application, then follow its own guide sequence.

## Import a vocabulary

```recurloop
import shell
let run_example = fn () -> i64 {
    return run printf \"hello\\n\"
}
assert run_example() == 0
```

Import by name loads the corresponding installed engine image. Keep the image's dependencies available with it. Importing a library can add syntax as well as functions; explicit selectors help when vocabularies accept overlapping forms.

## Choose a library

| Task | Start here |
| --- | --- |
| Processes, pipelines and captured output | [Shell](../../../libraries/shell/docs/usage.rl) |
| Type-light function specialization | [Inferred](../../../libraries/inferred/docs/usage.rl) |
| Phrase parsing, text and managed values | [LanguageKit](../../../libraries/language-kit/docs/usage.rl) |
| HTTP request handling | [Http](../../../libraries/http/docs/usage.rl) |
| Application targets and debugging | [Project](../../../libraries/project/docs/usage.rl) |
| Windows, widgets and editor views | [Gui](../../../libraries/gui/docs/usage.rl), [IDE](../../../libraries/ide/docs/usage.rl) |
| Embedded bits and native graphics | [Embed](../../../libraries/embed/docs/usage.rl), [Window](../../../libraries/window/docs/usage.rl), [Vulkan](../../../libraries/vulkan/docs/usage.rl) |
| Public help, search and portable manuals | [Docs](../../../libraries/docs/docs/usage.rl) |

## Reuse source files

`include` evaluates source in the current language context. An imported image restores a previously exported vocabulary. Choose source inclusion for source-level composition and images for a reusable packaged vocabulary; neither implies that arbitrary native resources can be persisted in an image."
    }
]
