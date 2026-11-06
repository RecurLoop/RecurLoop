// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:layout = [
    id = phrase { payload = "layout" }
    title = phrase { payload = "Compose layouts, panes, tabs and stacks" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`column` and `row` create boxes with spacing in pixels. `append(box, child, grow, padding)` attaches a child at the start; `append_end` packs it at the end. `grow` controls expansion and padding adds surrounding space.

```recurloop
import gui
let build_form = fn () -> u8* {
    let root = Gui:column(12)
    if !root { return cast(u8*, 0) }
    let actions = Gui:row(8)
    Gui:append(root, Gui:input(\"Package name\"), 0, 0)
    Gui:append(actions, Gui:button(\"Cancel\"), 0, 0)
    Gui:append_end(actions, Gui:button(\"Save\"), 0, 0)
    Gui:append(root, actions, 0, 0)
    return root
}
```

Call this after successful initialization. The returned root belongs to the caller until attached to another container. Destroying that root releases its attached children; do not separately free a child pointer after attachment.

## Select a container for the job

| Container | Purpose | Selection API |
| --- | --- | --- |
| row / column | horizontal / vertical layout | no active child |
| horizontal / vertical split | user-resizable pair | `split_first`, `split_second`, `split_position` |
| tabs | named pages | `tabs_select` with zero-based index |
| stack | one visible child | `stack_select` with child pointer |
| scroll | scrolling content | child supplied to `scroll` |

Use expansion and alignment separately: expansion requests extra space; alignment positions a widget within its allocation. `size` requests a minimum size, with `-1` leaving a dimension to the toolkit. Read allocated dimensions only after layout when actual pixel size matters."
    }
]
