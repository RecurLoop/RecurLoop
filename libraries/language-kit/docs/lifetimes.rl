// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:lifetimes = [
    id = phrase { payload = "lifetimes" }
    title = phrase { payload = "Managed scopes, strong references and weak handles" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "Use `Lifetime` for resources tied to a language evaluation scope. Enter nested scopes and leave them in reverse order. Leaving releases that scope's strong references; a payload is destroyed when its last strong reference is gone.

```recurloop
import language-kit
let scoped_storage = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let scope = LanguageKit:Lifetime:enter(state)
        if !scope { context:diagnostic:error(state, \"scope allocation failed\"); return }
        defer LanguageKit:Lifetime:leave(state, scope)
        let bytes = LanguageKit:Lifetime:alloc_raw(state, 16)
        if !bytes { context:diagnostic:error(state, \"managed allocation failed\"); return }
        bytes[0] = 42
    }
}
scoped_storage
```

Do not free `bytes`: scope exit owns that release. `retain` adds a current-scope reference, `release` removes one, `move_to_parent` transfers it upward and `promote_root` gives it root lifetime. Check return values when a transfer is required for correctness.

## Adopted resources and weak access

`adopt` transfers an existing allocation with a cleanup callback. For a valid allocation its failure path also invokes cleanup; do not free that resource again. A cleanup callback receives the context, pointer and supplied userdata.

`weak` creates a weak handle without keeping its payload alive. `weak_lock` either returns null or acquires a current-scope strong reference. Release a successful lock as a managed reference; destroy the weak handle separately with `weak_destroy`. A weak handle is not a raw pointer that remains valid after expiration."
    }
]
