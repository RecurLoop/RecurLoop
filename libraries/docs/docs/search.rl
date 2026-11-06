// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:search = [
    id = phrase { payload = "search" }
    title = phrase { payload = "Search catalogs and reuse their indexes" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Docs:search(store, query, after)` returns a borrowed entry. Pass null for the first result, then the preceding result to continue. Keep the query stable during that iteration.

```recurloop
import docs
let count_matches = fn () -> i64 {
    let store = Docs:new(\"sample\", \"1.0.0\", \"\")
    if !store { return -1 }
    defer Docs:destroy(store)
    if !Docs:add(store, \"sample\", \"text\", \"Text buffers\", \"Guides\", \"Owned text buffers transfer strings.\", \"\", \"\") { return -1 }
    if !Docs:add(store, \"sample\", \"jobs\", \"Background jobs\", \"Guides\", \"Owned jobs provide exit status.\", \"\", \"\") { return -1 }
    var count = 0
    var found = Docs:search(store, \"own text\", cast(Docs:Entry*, 0))
    while found {
        count += 1
        found = Docs:search(store, \"own text\", found)
    }
    return count
}
assert count_matches() == 1
```

## Matching contract

Words use ASCII case folding and prefix matches. Every query word must match a word in the entry; `own text` matches ownership-related text entries but not a job page containing only `owned`. Phrase punctuation separates word tokens; exact phrase titles remain useful for symbol lookup.

The normalization identifier is `ascii-word-prefix-v1`. Non-ASCII word bytes are preserved; there is no promise of accent removal, stemming or language-aware Unicode case folding. Native search does not silently add the website's typo suggestions.

`build_index` reuses a ready index. Editing invalidates it and the next query rebuilds it. `read_export` reads existing postings instead of tokenizing every body again. Search results remain borrowed and become invalid when their store is destroyed."
    }
]
