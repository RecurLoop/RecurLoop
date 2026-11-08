let Docs:Pages:overview = [
    id = phrase { payload = "overview" }
    title = phrase { payload = "My application" }
    section = phrase { payload = "Guides" }
    default = phrase { payload = "true" }
    order = phrase { payload = "10" }
    body = phrase {
        payload = "## Run the application

Run `recurloop --target run` from the project directory. The application prints
`42` and exits successfully.

## Test and build

Use `recurloop --target test` to check the answer. Use `recurloop --target build`
to create `build/app`, then run `./build/app`.

## Export this manual

Run `recurloop --target docs`. The portable bundle in
`build/docs/my-application.json` contains this guide, API help and a search index."
    }
]
