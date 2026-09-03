// ============================================================================
// RecurLoop Number Lab
//
// Build:
//   make example EXAMPLE=05-applications/number-lab BUILD_TYPE=Release
//
// Run:
//   /tmp/recurloop-number-lab 100
//
// Example:
//   Number Lab
//   input: 100
//
//   primes:
//   2
//   3
//   5
//   ...
//
//   prime count: 25
//   prime sum: 1060
//   largest prime: 97
//   gcd(input, 360): 20
//   digit sum: 1
//   collatz steps: 25
// ============================================================================


// ============================================================================
// Minimal standalone support
// ============================================================================

module auto
module clear

emit object "/tmp/recurloop-number-lab-support.o" = asm {

.text


// ----------------------------------------------------------------------------
// atoi(text:u8*) -> i64
// ----------------------------------------------------------------------------

atoi:
    xor rax, rax
    xor r8, r8

    cmp byte [rdi], 45
    jne atoi_digits

    mov r8, 1
    inc rdi

atoi_digits:
    movzx ecx, byte [rdi]
    sub ecx, 48

    cmp ecx, 9
    ja atoi_done

    imul rax, rax, 10
    add rax, rcx

    inc rdi
    jmp atoi_digits

atoi_done:
    test r8, r8
    je atoi_return

    neg rax

atoi_return:
    ret


// ----------------------------------------------------------------------------
// print_string(text:u8*) -> i64
// ----------------------------------------------------------------------------

print_string:
    mov rsi, rdi
    xor rdx, rdx

print_string_length:
    cmp byte [rsi + rdx], 0
    je print_string_write

    inc rdx
    jmp print_string_length

print_string_write:
    mov rax, 1
    mov rdi, 1
    syscall
    ret


// ----------------------------------------------------------------------------
// print_i64(value:i64) -> i64
//
// Decimal + newline.
// ----------------------------------------------------------------------------

print_i64:
    sub rsp, 64

    lea r8, [rsp + 63]

    mov byte [r8], 10
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


// ============================================================================
// Import support functions
// ============================================================================

link object "/tmp/recurloop-number-lab-support.o"

extern atoi(text:u8*) -> i64 abi sysv-amd64
extern print_string(text:u8*) -> i64 abi sysv-amd64
extern print_i64(value:i64) -> i64 abi sysv-amd64


// ============================================================================
// Native algorithms
// ============================================================================


// ----------------------------------------------------------------------------
// gcd
// ----------------------------------------------------------------------------

let gcd = fn (a:i64, b:i64) -> i64 {
    while b != 0 {
        var remainder = a % b
        a = b
        b = remainder
    }

    return a
}


// ----------------------------------------------------------------------------
// digit_sum
//
// 12345 -> 15
// ----------------------------------------------------------------------------

let digit_sum = fn (value:i64) -> i64 {
    if value < 0 {
        value = -value
    }

    var result = 0

    while value != 0 {
        result += value % 10
        value /= 10
    }

    return result
}


// ----------------------------------------------------------------------------
// collatz_steps
//
// Number of transformations necessary to reach 1.
//
// 6:
//   6 -> 3 -> 10 -> 5 -> 16 -> 8 -> 4 -> 2 -> 1
//
// result = 8
// ----------------------------------------------------------------------------

let collatz_steps = fn (value:i64) -> i64 {
    var steps = 0

    while value > 1 {
        if value % 2 == 0 {
            value /= 2
        } else {
            value = value * 3 + 1
        }

        steps += 1
    }

    return steps
}


// ----------------------------------------------------------------------------
// is_prime
//
// returns:
//   1 = prime
//   0 = not prime
//
// We only test divisors while divisor * divisor <= value.
// ----------------------------------------------------------------------------

let is_prime = fn (value:i64) -> i64 {
    if value < 2 {
        return 0
    } else {
        if value == 2 {
            return 1
        } else {
            if value % 2 == 0 {
                return 0
            } else {
                var divisor = 3

                while divisor * divisor <= value {
                    if value % divisor == 0 {
                        return 0
                    }

                    divisor += 2
                }

                return 1
            }
        }
    }
}


// ----------------------------------------------------------------------------
// count_primes
// ----------------------------------------------------------------------------

let count_primes = fn (limit:i64) -> i64 {
    var candidate = 2
    var count = 0

    while candidate <= limit {
        if is_prime(candidate) == 1 {
            count += 1
        }

        candidate += 1
    }

    return count
}


// ----------------------------------------------------------------------------
// sum_primes
// ----------------------------------------------------------------------------

let sum_primes = fn (limit:i64) -> i64 {
    var candidate = 2
    var sum = 0

    while candidate <= limit {
        if is_prime(candidate) == 1 {
            sum += candidate
        }

        candidate += 1
    }

    return sum
}


// ----------------------------------------------------------------------------
// largest_prime
// ----------------------------------------------------------------------------

let largest_prime = fn (limit:i64) -> i64 {
    var candidate = limit

    while candidate >= 2 {
        if is_prime(candidate) == 1 {
            return candidate
        }

        candidate -= 1
    }

    return 0
}


// ----------------------------------------------------------------------------
// print_primes
// ----------------------------------------------------------------------------

let print_primes = fn (limit:i64) -> i64 {
    var candidate = 2
    var count = 0

    while candidate <= limit {
        if is_prime(candidate) == 1 {
            print_i64(candidate)
            count += 1
        }

        candidate += 1
    }

    return count
}


// ============================================================================
// Standalone application
// ============================================================================

module auto
module clear

emit executable "/tmp/recurloop-number-lab" number_lab = fn (argc:i64, argv:u8**) -> i64 {
    if argc <= 1 {
        print_string("RecurLoop Number Lab\n")
        print_string("\n")
        print_string("usage:\n")
        print_string("  recurloop-number-lab <positive integer>\n")
        print_string("\n")
        print_string("example:\n")
        print_string("  recurloop-number-lab 100\n")

        return 1
    } else {
        var input = atoi(argv[1])

        if input <= 0 {
            print_string("error: value must be greater than zero\n")
            return 2
        } else {

            // ---------------------------------------------------------------
            // Header
            // ---------------------------------------------------------------

            print_string("========================================\n")
            print_string("        RecurLoop Number Lab\n")
            print_string("========================================\n")
            print_string("\n")

            print_string("input:\n")
            print_i64(input)

            print_string("\n")


            // ---------------------------------------------------------------
            // Prime enumeration
            // ---------------------------------------------------------------

            print_string("----------------------------------------\n")
            print_string("prime numbers\n")
            print_string("----------------------------------------\n")

            var printed_prime_count = print_primes(input)

            print_string("\n")


            // ---------------------------------------------------------------
            // Prime statistics
            // ---------------------------------------------------------------

            print_string("----------------------------------------\n")
            print_string("prime statistics\n")
            print_string("----------------------------------------\n")

            print_string("prime count:\n")
            print_i64(printed_prime_count)

            print_string("prime sum:\n")
            print_i64(sum_primes(input))

            print_string("largest prime <= input:\n")
            print_i64(largest_prime(input))

            print_string("\n")


            // ---------------------------------------------------------------
            // Number properties
            // ---------------------------------------------------------------

            print_string("----------------------------------------\n")
            print_string("number properties\n")
            print_string("----------------------------------------\n")

            print_string("digit sum:\n")
            print_i64(digit_sum(input))

            print_string("gcd(input, 360):\n")
            print_i64(gcd(input, 360))

            print_string("collatz steps:\n")
            print_i64(collatz_steps(input))

            print_string("\n")


            // ---------------------------------------------------------------
            // Direct primality
            // ---------------------------------------------------------------

            print_string("----------------------------------------\n")
            print_string("input classification\n")
            print_string("----------------------------------------\n")

            if is_prime(input) == 1 {
                print_string("input is PRIME\n")
            } else {
                print_string("input is NOT PRIME\n")
            }

            print_string("\n")
            print_string("done\n")

            return 0
        }
    }
}

link clear


// ============================================================================
// Compiler statistics
// ============================================================================

debug:stats
