// =============================================================================
// RecurLoop CIDR Info
//
// Standalone IPv4 subnet calculator for Linux x86-64.
//
// Build:
//   make example EXAMPLE=05-applications/cidr-calculator
//
// Run:
//   /tmp/recurloop-cidr 192.168.10.42 24
//   /tmp/recurloop-cidr 10.20.30.40 16
// =============================================================================


// -----------------------------------------------------------------------------
// Minimal output runtime.
// -----------------------------------------------------------------------------

module auto
module clear
module strip
emit object "/tmp/recurloop-cidr-runtime.o" = asm {
.text

// i64 print_text(const u8* text, u64 length)
print_text:
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    mov rax, 1
    syscall
    ret

// i64 print_i64(i64 value, i64 suffix)
// suffix: 0 = none, 10 = newline, 32 = space, 46 = dot.
print_i64:
    sub rsp, 64
    lea r8, [rsp + 63]
    xor rcx, rcx

    test rsi, rsi
    je print_i64_prepare
    mov byte [r8], sil
    mov rcx, 1

print_i64_prepare:
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

link object "/tmp/recurloop-cidr-runtime.o"
extern print_text(text:u8*, length:u64) -> i64 abi sysv-amd64
extern print_i64(value:i64, suffix:i64) -> i64 abi sysv-amd64


// -----------------------------------------------------------------------------
// Tekst i liczby.
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

let is_decimal = fn (text:u8*) -> i64 {
    var index = 0

    if text[0] == 0 {
        return 0
    }

    while text[index] != 0 {
        if text[index] < 48 {
            return 0
        }

        if text[index] > 57 {
            return 0
        }

        index += 1
    }

    return 1
}

let parse_decimal = fn (text:u8*) -> i64 {
    var index = 0
    var result = 0

    while text[index] != 0 {
        result = result * 10 + text[index] - 48
        index += 1
    }

    return result
}

let power_of_two = fn (exponent:i64) -> i64 {
    var result = 1
    var index = 0

    while index < exponent {
        result *= 2
        index += 1
    }

    return result
}


// -----------------------------------------------------------------------------
// Parser IPv4.
//
// Returns 0..4294967295, or -1 for an invalid address.
// -----------------------------------------------------------------------------

let parse_ipv4 = fn (text:u8*) -> i64 {
    var index = 0
    var part = 0
    var address = 0

    while part < 4 {
        var octet = 0
        var digits = 0

        while text[index] >= 48 {
            if text[index] > 57 {
                return -1
            }

            octet = octet * 10 + text[index] - 48
            digits += 1
            index += 1

            if octet > 255 {
                return -1
            }

            if digits > 3 {
                return -1
            }
        }

        if digits == 0 {
            return -1
        }

        address = address * 256 + octet

        if part < 3 {
            if text[index] != 46 {
                return -1
            }

            index += 1
        } else {
            if text[index] != 0 {
                return -1
            }
        }

        part += 1
    }

    return address
}


// -----------------------------------------------------------------------------
// Formatowanie i klasyfikacja IPv4.
// -----------------------------------------------------------------------------

let print_ipv4 = fn (address:i64, suffix:i64) -> i64 {
    var first = address / 16777216
    var rest = address % 16777216
    var second = rest / 65536
    rest %= 65536
    var third = rest / 256
    var fourth = rest % 256

    print_i64(first, 46)
    print_i64(second, 46)
    print_i64(third, 46)
    print_i64(fourth, suffix)

    return 0
}

let print_address_scope = fn (address:i64) -> i64 {
    if address == 0 {
        write_text("unspecified\n")
        return 0
    }

    if address == 4294967295 {
        write_text("limited broadcast\n")
        return 0
    }

    if address >= 167772160 {
        if address <= 184549375 {
            write_text("private (10.0.0.0/8)\n")
            return 0
        }
    }

    if address >= 2886729728 {
        if address <= 2887778303 {
            write_text("private (172.16.0.0/12)\n")
            return 0
        }
    }

    if address >= 3232235520 {
        if address <= 3232301055 {
            write_text("private (192.168.0.0/16)\n")
            return 0
        }
    }

    if address >= 2130706432 {
        if address <= 2147483647 {
            write_text("loopback\n")
            return 0
        }
    }

    if address >= 2851995648 {
        if address <= 2852061183 {
            write_text("link-local\n")
            return 0
        }
    }

    if address >= 3758096384 {
        if address <= 4026531839 {
            write_text("multicast\n")
            return 0
        }
    }

    write_text("public or special-use\n")
    return 0
}


// -----------------------------------------------------------------------------
// Program wynikowy.
// -----------------------------------------------------------------------------

module auto
module clear
module strip
module entry cidr_main
emit executable "/tmp/recurloop-cidr" cidr_main = fn (argc:i64, argv:u8**) -> i64 {
    if argc != 3 {
        write_text("usage: ")
        write_text(argv[0])
        write_text(" <ipv4-address> <prefix>\n")
        write_text("example: ")
        write_text(argv[0])
        write_text(" 192.168.10.42 24\n")
        return 2
    }

    var address = parse_ipv4(argv[1])

    if address < 0 {
        write_text("error: invalid IPv4 address\n")
        return 2
    }

    if is_decimal(argv[2]) == 0 {
        write_text("error: prefix must be an integer from 0 to 32\n")
        return 2
    }

    if cstrlen(argv[2]) > 2 {
        write_text("error: prefix must be an integer from 0 to 32\n")
        return 2
    }

    var prefix = parse_decimal(argv[2])

    if prefix > 32 {
        write_text("error: prefix must be an integer from 0 to 32\n")
        return 2
    }

    var host_bits = 32 - prefix
    var block_size = power_of_two(host_bits)
    var wildcard = block_size - 1
    var netmask = 4294967295 - wildcard
    var network = address / block_size * block_size
    var broadcast = network + wildcard
    var first_host = network
    var last_host = broadcast
    var usable_hosts = block_size

    if prefix < 31 {
        first_host = network + 1
        last_host = broadcast - 1
        usable_hosts = block_size - 2
    }

    write_text("RecurLoop CIDR Info\n")
    write_text("-------------------\n")

    write_text("address:         ")
    print_ipv4(address, 10)

    write_text("prefix:          /")
    print_i64(prefix, 10)

    write_text("scope:           ")
    print_address_scope(address)

    write_text("netmask:         ")
    print_ipv4(netmask, 10)

    write_text("wildcard:        ")
    print_ipv4(wildcard, 10)

    write_text("network:         ")
    print_ipv4(network, 10)

    write_text("broadcast:       ")
    print_ipv4(broadcast, 10)

    write_text("first host:      ")
    print_ipv4(first_host, 10)

    write_text("last host:       ")
    print_ipv4(last_host, 10)

    write_text("total addresses: ")
    print_i64(block_size, 10)

    write_text("usable hosts:    ")
    print_i64(usable_hosts, 10)

    return 0
}

link clear
