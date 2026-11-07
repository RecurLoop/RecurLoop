// Extended public documentation. Navigation, rendered blocks and indexes are generated.

let Docs:Pages:root_paths = [
    id = phrase { payload = "root-paths" }
    title = phrase { payload = "Project paths" }
    section = phrase { payload = "Guides" }
    order = phrase { payload = "30" }
    body = phrase {
        payload = "## Resolve paths from the application root

`Project:root()` returns the root provided through `RECURLOOP_PROJECT_ROOT`. It returns null when no project root is configured. The returned environment string is borrowed and must not be freed.

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

## Distinguish source and process paths

Keep project-relative configuration explicit. A path relative to a source file, a process working directory and a project root are different concepts. Pass the intended base into helpers that construct paths, and check whether the root is available rather than silently substituting a different directory.

## Keep borrowed paths valid

Copy the root string if it must survive an environment change. For temporary process-directory changes, use Shell directory guards; reading `Project:root` does not itself change the working directory."
    }
]
