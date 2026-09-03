// =============================================================================
// RecurLoop lexicons as compiled dictionary fragments
// =============================================================================
//
// This example demonstrates the public model:
//
//   1. `lexicon { ... }` is assigned by `let`.
//   2. Compilation starts when the definition closes.
//   3. `merge <name>` accepts lexicons and ordinary dictionaries.
//   4. The merge target is the currently active dictionary.
//   5. A compiled lexicon can be merged into multiple locations.
//   6. Merged content becomes part of the active phrase graph.
//
// Demo phrases alias `debug:ping` so the example stays focused on composition.
//
// Run:
//   make example EXAMPLE=03-phrases-and-syntax/lexicon-composition
// =============================================================================


// -----------------------------------------------------------------------------
// An ordinary dictionary can use the same merge operation as a lexicon.
// -----------------------------------------------------------------------------

let local_dictionary = [
    local = <debug:ping>
    shared = [
        ready = <debug:ping>
    ]
]


// -----------------------------------------------------------------------------
// Two independent lexicons begin compiling when their definitions close.
// -----------------------------------------------------------------------------

let http_lexicon = lexicon {
    let api = [
        get = <debug:ping>
        post = <debug:ping>
        health = [
            live = <debug:ping>
        ]
    ]

    let version = <debug:ping>
}

let observability_lexicon = lexicon {
    let metrics = [
        requests = <debug:ping>
        latency = [
            p50 = <debug:ping>
            p99 = <debug:ping>
        ]
    ]
}


// -----------------------------------------------------------------------------
// Merge w root.
//
// Merge waits for the complete compiled graph. local_dictionary follows the
// same path despite being an ordinary dictionary.
// -----------------------------------------------------------------------------

let application = [
    merge <local_dictionary>
    merge <http_lexicon>
    merge <observability_lexicon>
]

print "[root] local="
application:local
print "[root] http="
application:api:get
print "[root] nested="
application:api:health:live
print "[root] metrics="
application:metrics:latency:p99


// -----------------------------------------------------------------------------
// Merge into a nested active dictionary, then reuse the same compiled lexicon.
// -----------------------------------------------------------------------------

let mirrored = [
    endpoints = [
        merge <http_lexicon>
        merge <local_dictionary>
        local_only = <debug:ping>
    ]
]

print "[nested] http="
mirrored:endpoints:api:post
print "[nested] local="
mirrored:endpoints:local
print "[nested] own="
mirrored:endpoints:local_only


// -----------------------------------------------------------------------------
// Reusing the source is idempotent. Merged phrases are directly visible in the
// active dictionary without an extra wrapper level.
// -----------------------------------------------------------------------------

let flattened = [
    merge <observability_lexicon>
    merge <observability_lexicon>
]

print "[flat] p50="
flattened:metrics:latency:p50
print "[flat] requests="
flattened:metrics:requests

print "lexicon composition complete"
