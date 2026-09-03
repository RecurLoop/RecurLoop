let library = lexicon {
    let alpha = <debug:ping>
    let nested = [
        beta = <debug:ping>
    ]
}

let merged = [
    merge <library>
    gamma = <debug:ping>
]

merged:alpha
merged:nested:beta
merged:gamma

let source = [
    delta = <debug:ping>
]
let direct = [
    merge <source>
]
direct:delta
