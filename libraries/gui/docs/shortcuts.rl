// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:shortcuts = [
    id = phrase { payload = "shortcuts" }
    title = phrase { payload = "Shortcuts, prompts and confirmation dialogs" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Connect a window shortcut to an existing button action instead of implementing a second copy of that action. `Key` and `Modifier` helpers supply backend values.

```recurloop
import gui
let add_save_shortcut = fn (window:u8*, save:u8*) -> void {
    Gui:shortcut_click(window, save, Gui:Key:S(), Gui:Modifier:Control())
}
```

For event callbacks, inspect `event_key`, `event_button` and `event_modifiers`. Return nonzero only when your callback handled the event; otherwise preserve normal widget behavior.

## Distinguish cancellation and returned text

```recurloop
import gui
let ask_name = fn (parent:u8*) -> i64 {
    let name = Gui:prompt(parent, \"New name\", \"Enter a name\", \"\")
    if !name { return 0 }
    defer free(name)
    if name[0] == 0 { return 0 }
    printf(\"name: %s\\n\", name)
    return 1
}
```

`prompt` returns malloc-owned text, so use `free`; a null result means cancellation or failure. This differs from `text_get`, whose result uses `Gui:text_free`. `confirm` returns `1` for the named affirmative action and `0` otherwise. Treat an empty confirmed prompt separately from cancellation when the application permits empty values."
    }
]
