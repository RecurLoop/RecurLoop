// Public usage guide. Navigation and indexes are generated from this object.

let Docs:Pages:values = [
    id = phrase { payload = "values" }
    title = phrase { payload = "Values" }
    section = phrase { payload = "Language" }
    order = phrase { payload = "100" }
    body = phrase {
        payload = "Runtime bindings hold values; native function parameters use explicit machine types. Start with `var` and `const`, then use expressions to compute a new value.

## Runtime values

Runtime values are `null`, `bool`, `int`, `real`, and `string`.

The `recurloop_version` phrase returns the running host's release version as a
`string`, without a `v` prefix. It reads the host version on evaluation rather
than storing a version in the language image:

```recurloop
var version = recurloop_version
print version
```

This prints the version exposed by the running language.

```recurloop
const project = \"Recur\" + \"Loop\"
var result = 2 + 3 * 4
result += 7

assert result == 21
print project + \": \" + str(result)
```

## Operators and precedence

Operator precedence, from highest to lowest:

1. unary `!`, `~`, `+`, `-`;
2. `*`, `/`, `%`;
3. `+`, `-`;
4. `<<`, `>>`;
5. `<`, `<=`, `>`, `>=`;
6. `==`, `!=`;
7. bitwise `&`;
8. bitwise `^`;
9. bitwise `|`;
10. `&&`;
11. `||`.

Primary and postfix syntax is phrase-backed too. The standard runtime-expression
grammar declares grouping as a primary phrase and qualification, calls, and
member calls as postfix phrases. Compiled `fn` expressions use the corresponding
phrase dictionaries, so aliases of structural tokens work consistently in both
paths instead of being recognized by spelling-specific parser branches.

## Numeric and string behavior

Integer arithmetic checks overflow and division by zero. Mixed numeric
operations produce `real`. String addition concatenates, and boolean operators
short-circuit.

Bitwise operators require integers. `~` inverts bits, while `&`, `|`, and `^`
combine bits. `<<` shifts left, and `>>` shifts right arithmetically for signed
types and logically for unsigned types. Shift counts are reduced modulo the
left operand's bit width. Left shifts discard bits past that width. The top-level
`int` has 64 bits. Compound assignments
`&=`, `|=`, `^=`, `<<=`, and `>>=` use the same operations.

## Mutation and lexical scope

`var` is mutable, `const` is immutable, and assignment updates the nearest
visible binding. Function bodies, branches, loops, and explicit blocks create
lexical value scopes."
    }
]
