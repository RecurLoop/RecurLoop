// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:trees = [
    id = phrase { payload = "trees" }
    title = phrase { payload = "Trees" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "60" }
    body = phrase {
        payload = "## Create rows and release iterators

`tree` creates a file-style tree with labels, paths and directory state. `tree_append` returns an allocated iterator. Freeing the iterator releases its wrapper, not the row in the model.

```recurloop
import gui
let add_root = fn (tree:u8*) -> i64 {
    let row = Gui:tree_append(tree, cast(u8*, 0), \"Sources\", \"src\", 1)
    if !row { return 0 }
    defer Gui:tree_iter_free(row)
    Gui:tree_mark_loaded(tree, row)
    return 1
}
let print_selected_path = fn (tree:u8*) -> i64 {
    var directory:i32 = 0
    let path = Gui:tree_selected_path(tree, &directory)
    if !path { return 0 }
    defer Gui:text_free(path)
    printf(\"selected: %s\\n\", path)
    return 1
}
```

## Populate directories lazily

Null parent adds a root row. To populate a directory lazily, append its children, then mark that directory loaded; a loaded flag is application bookkeeping, not a filesystem scan.

## Read selection and paths

`tree_selection` returns a borrowed selection object; `tree_selected_iter` returns an owned iterator, or null for no selection. `tree_iter_path` and `tree_selected_path` return owned text released with `Gui:text_free`. Clear operations invalidate iterators for removed rows. Never keep an iterator across `tree_clear` or deletion of its row."
    }
]
