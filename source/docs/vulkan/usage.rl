// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Vulkan" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Vulkan provides typed RecurLoop bindings for graphics resources and commands.

## Ownership

Create dependent resources only while their parent instance or device remains alive. Release resources in the reverse order of their dependencies. Wait for outstanding work before destroying resources it uses.

## Result values

Check result codes before reading output handles. Structure fields and pointer lifetimes follow the associated API descriptions."
    }
]

