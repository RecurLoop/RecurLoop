// =============================================================================
// Python-style functions built from RecurLoop phrases
//
// `def` is not a host-language keyword. It is a normal phrase alias for the
// existing function compiler action. The only syntax adapter is indentation:
// a header ending in `:` owns the following indented lines, and dedentation
// closes that block before the ordinary RecurLoop parser sees it.
//
// The rest of the language remains phrase-driven. These spellings are all
// user-level aliases and can be changed without recompiling the host:
//   def       -> fn
//   done      -> return
//   branch    -> if
//   otherwise -> else
//   plus      -> +
//   repeat    -> while
//   addTo     -> +=
//
// Expected output:
//   5
//   13
//   1
//   42
//   10
// =============================================================================

let def = <fn>
let done = <return>
let branch = <if>
let otherwise = <else>
let plus = <+>
let repeat = <while>
let addTo = <+=>

def add(left:i64, right:i64) -> i64:
    done left plus right

def classify(value:i64) -> i64:
    branch value > 2:
        done value plus 10
    otherwise:
        done 1

def sumTo(value:i64) -> i64:
    var total:i64 = 0
    repeat value > 0:
        total addTo value
        value -= 1
    done total

// A function can also be created as a value. Its body uses exactly the same
// indentation rules, and `make` is just another spelling of `fn`.
let make = <fn>
let increment = make (value:i64) -> i64:
    done value plus 1

assert add(2, 3) == 5
assert classify(3) == 13
assert classify(1) == 1
assert increment(41) == 42
assert sumTo(4) == 10

print add(2, 3)
print classify(3)
print classify(1)
print increment(41)
print sumTo(4)
