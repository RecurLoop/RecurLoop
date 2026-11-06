// Extended usage documentation. The catalog and index are generated from these objects.

let Docs:Pages:usage = [
    symbol = phrase { payload = "IDE" }
    section = phrase { payload = "API" }
    default = phrase { payload = "true" }
    body = phrase {
        payload = "IDE provides configurable editor views, terminals, source intelligence and reload behavior as RecurLoop objects.

Create an `IDE:Config`, configure the workspace and view lifecycle, then open it. Release the configuration after its lifecycle is finished. Source intelligence uses the active vocabulary, including custom phrases and their `.docs` metadata."
    }
]

