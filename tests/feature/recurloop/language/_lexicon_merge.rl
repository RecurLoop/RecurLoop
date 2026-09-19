let library = lexicon {
    let alpha = <debug:ping>
    let nested = [
        beta = <debug:ping>
    ]
}

engine export <library> "/tmp/recurloop-lexicon-fragment-test.rli"

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

let restored = [
    merge "/tmp/recurloop-lexicon-fragment-test.rli"
]
restored:alpha
restored:nested:beta
