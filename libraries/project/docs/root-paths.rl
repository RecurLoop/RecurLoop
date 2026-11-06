// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:root_paths = [
    id = phrase { payload = "root-paths" }
    title = phrase { payload = "Resolve application paths from the project root" }
    section = phrase { payload = "Guides" }
    body = phrase {
        payload = "`Project:root()` returns the root provided through `RECURLOOP_PROJECT_ROOT`. It returns null when no project root is configured. The returned environment string is borrowed and must not be freed.

```recurloop
import project
import language-kit
let show_project_root = fn () -> i64 {
    let root = Project:root()
    if !root { return 1 }
    printf(\"project root: %s\\n\", root)
    return 0
}
```

Keep project-relative configuration explicit. A path relative to a source file, a process working directory and a project root are different concepts. Pass the intended base into helpers that construct paths, and check whether the root is available rather than silently substituting a different directory.

Copy the root string if it must survive an environment change. For temporary process-directory changes, use Shell directory guards; reading `Project:root` does not itself change the working directory."
    }
]
