// =============================================================================
// RecurLoop NumInfo
//
// Standalone Linux x86-64 command-line tool.
//
// Build:
//   make example EXAMPLE=05-applications/number-inspector
//
// Run:
//   /tmp/recurloop-numinfo 360
//   /tmp/recurloop-numinfo -9973
// =============================================================================


// -----------------------------------------------------------------------------
// Minimal syscall runtime for text and integer output. This produces an ELF64
// relocatable object that is linked into the final program.
// -----------------------------------------------------------------------------

module auto
module clear
module strip
emit object "/tmp/recurloop-numinfo-runtime.o" = asm {
.text

// i64 print_text(const u8* text, u64 length)
print_text:
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    mov rax, 1
    syscall
    ret

// i64 print_i64(i64 value, u8 suffix)
// Print a decimal integer followed by a space or newline.
print_i64:
    sub rsp, 64
    lea r8, [rsp + 63]
    mov byte [r8], sil
    mov rcx, 1

    mov rax, rdi
    xor r9, r9
    test rax, rax
    jns print_i64_magnitude
    mov r9, 1
    neg rax

print_i64_magnitude:
    mov r10, 10

print_i64_digits:
    xor rdx, rdx
    div r10
    add dl, 48
    dec r8
    mov byte [r8], dl
    inc rcx
    test rax, rax
    jne print_i64_digits

    test r9, r9
    je print_i64_write
    dec r8
    mov byte [r8], 45
    inc rcx

print_i64_write:
    mov rax, 1
    mov rdi, 1
    mov rsi, r8
    mov rdx, rcx
    syscall

    add rsp, 64
    ret
}

link object "/tmp/recurloop-numinfo-runtime.o"
extern print_text(text:u8*, length:u64) -> i64 abi sysv-amd64
extern print_i64(value:i64, suffix:u8) -> i64 abi sysv-amd64


// -----------------------------------------------------------------------------
// Helper functions compiled from `fn`.
// -----------------------------------------------------------------------------

let cstrlen = fn (text:u8*) -> i64 {
    var index = 0

    while text[index] != 0 {
        index += 1
    }

    return index
}

let write_text = fn (text:u8*) -> i64 {
    return print_text(text, cstrlen(text))
}

let is_decimal_integer = fn (text:u8*) -> i64 {
    var index = 0

    if text[0] == 45 {
        index = 1
    }

    if text[index] == 0 {
        return 0
    }

    while text[index] != 0 {
        if text[index] < 48 || text[index] > 57 {
            return 0
        }

        index += 1
    }

    return 1
}

let parse_decimal_i64 = fn (text:u8*) -> i64 {
    var index = 0
    var sign = 1
    var result = 0

    if text[0] == 45 {
        sign = -1
        index = 1
    }

    while text[index] != 0 {
        result = result * 10 + text[index] - 48
        index += 1
    }

    return result * sign
}

let magnitude_i64 = fn (value:i64) -> i64 {
    if value < 0 {
        return -value
    } else {
        return value
    }
}

let digit_count = fn (value:i64) -> i64 {
    var number = magnitude_i64(value)
    var count = 0

    if number == 0 {
        return 1
    }

    while number > 0 {
        number /= 10
        count += 1
    }

    return count
}

let digit_sum = fn (value:i64) -> i64 {
    var number = magnitude_i64(value)
    var sum = 0

    while number > 0 {
        sum += number % 10
        number /= 10
    }

    return sum
}

let is_prime = fn (value:i64) -> i64 {
    // Negative integers are not prime.
    if value < 2 {
        return 0
    }

    var number = value

    if number == 2 {
        return 1
    }

    if number % 2 == 0 {
        return 0
    }

    var divisor = 3

    // This form avoids overflowing i64 in the loop condition.
    while divisor <= number / divisor {
        if number % divisor == 0 {
            return 0
        }

        divisor += 2
    }

    return 1
}

let divisor_count = fn (value:i64) -> i64 {
    var number = magnitude_i64(value)
    var result = 1
    var divisor = 2

    while divisor <= number / divisor {
        var exponent = 0

        while number % divisor == 0 {
            number /= divisor
            exponent += 1
        }

        if exponent > 0 {
            result *= exponent + 1
        }

        if divisor == 2 {
            divisor = 3
        } else {
            divisor += 2
        }
    }

    if number > 1 {
        result *= 2
    }

    return result
}

let print_factorization = fn (value:i64) -> i64 {
    var number = magnitude_i64(value)
    var divisor = 2

    if value < 0 {
        print_i64(-1, 32)
    }

    if number < 2 {
        write_text("none")
        return 0
    }

    while divisor <= number / divisor {
        while number % divisor == 0 {
            print_i64(divisor, 32)
            number /= divisor
        }

        if divisor == 2 {
            divisor = 3
        } else {
            divisor += 2
        }
    }

    if number > 1 {
        print_i64(number, 32)
    }
    return 0
}


// -----------------------------------------------------------------------------
// Program wynikowy.
//
// Input is limited to +/-2,000,000,000 so trial division completes promptly.
// -----------------------------------------------------------------------------

module auto
module clear
module strip
module entry numinfo_main
emit executable "/tmp/recurloop-numinfo" numinfo_main = fn (argc:i64, argv:u8**) -> i64 {
    if argc != 2 {
        write_text("usage: ")
        write_text(argv[0])
        write_text(" <integer>\n")
        return 2
    }

    var input = argv[1]

    // Check length first so the parser cannot overflow i64.
    if cstrlen(input) > 11 {
        write_text("error: integer is outside the supported range\n")
        return 2
    }

    if is_decimal_integer(input) == 0 {
        write_text("error: expected a base-10 integer\n")
        return 2
    }

    var value = parse_decimal_i64(input)

    if value < -2000000000 || value > 2000000000 {
        write_text("error: supported range is -2000000000..2000000000\n")
        return 2
    }

    var absolute = magnitude_i64(value)

    write_text("RecurLoop NumInfo\n")
    write_text("-----------------\n")

    write_text("input:         ")
    print_i64(value, 10)

    write_text("absolute:      ")
    print_i64(absolute, 10)

    write_text("parity:        ")
    if absolute % 2 == 0 {
        write_text("even\n")
    } else {
        write_text("odd\n")
    }

    write_text("prime:         ")
    if is_prime(value) == 1 {
        write_text("yes\n")
    } else {
        write_text("no\n")
    }

    write_text("digit count:   ")
    print_i64(digit_count(value), 10)

    write_text("digit sum:     ")
    print_i64(digit_sum(value), 10)

    write_text("divisor count: ")
    if absolute == 0 {
        write_text("undefined\n")
    } else {
        print_i64(divisor_count(value), 10)
    }

    write_text("factorization: ")
    print_factorization(value)
    write_text("\n")

    return 0
}

link clear

debug : stats
