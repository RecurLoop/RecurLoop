// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:text_inputs = [
    id = phrase { payload = "text-inputs" }
    title = phrase { payload = "Text and inputs" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "30" }
    body = phrase {
        payload = "## Read input and edit text

Single-line inputs and multiline text views have different accessors. `input_text` borrows the input's current text; `text_get` allocates a copy of a view's contents. Use `Gui:text_free` for that copy.

```recurloop
import gui
let copy_editor_to_label = fn (editor:u8*, label:u8*) -> i64 {
    let text = Gui:text_get(editor)
    if !text { return 0 }
    defer Gui:text_free(text)
    Gui:label_text(label, text)
    return 1
}
```

## Choose borrowed or owned text

Copy borrowed input text before changing its widget or keeping it beyond a callback. `editor` creates editable monospace content without wrapping; `text_view` creates read-only output, and `line_gutter` provides a separate line-number view. `text_set` replaces all content.

## Styling and positions

`text_style` creates a named tag owned by the text buffer. Apply it with `text_apply_style(view, tag, start, finish)`, where `[start, finish)` uses character offsets, not UTF-8 byte offsets. Recompute ranges after editing; old offsets can point at different text.

`text_position_at` maps widget-local pixels to a character offset and returns `-1` on failure. `text_event_line` returns a one-based line or `-1`. `text_scroll_end` is useful for append-style output after updating the buffer. A tag pointer must not outlive its owning buffer."
    }
]
