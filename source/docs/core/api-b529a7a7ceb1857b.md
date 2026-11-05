```recurloop
asm {
    instruction operands
    ...
}
```

Assembles native instructions and labels. Use it as a `let` definition or after an `emit` directive.

**Example**

```recurloop
let answer = asm {
    mov rax, 42
    ret
}
```


