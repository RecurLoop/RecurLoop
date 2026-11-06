// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "Window" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "Window provides window creation, input and surface-related operations. Importing the vocabulary does not create a window.

## Lifetimes

Initialize the window system, create the window and process events during its lifetime. Destroy dependent resources before the window they reference, then terminate the window system. Check availability and creation results before using handles."
    }
]

