// Shell supplies completion policy as an ordinary, serializable phrase action.
// Core and the line editor know only Completion:complete and its request API.
let Shell:Completion = []

record Shell:Completion:Input {
    start:u64
    token:Shell:Text*
    quote:u8
    opening:u8
    escaped:i64
    files:i64
    commands:i64
    phrases:i64
    implicit:i64
    root:u64
    words:Shell:Command*
    programmable:i64
    command_start:u64
}

let Shell:Completion:new_command = fn (input:Shell:Completion:Input*) -> void {
    Shell:Command:destroy(input.words)
    input.words = Shell:Command:new()
    input.programmable = 1
}

let Shell:Completion:reset = fn (input:Shell:Completion:Input*, next:u64) -> void {
    input.start = next
    input.token.length = 0
    input.token.data[0] = 0
    input.quote = 0
    input.escaped = 0
}

let Shell:Completion:alias = fn (state:Context*, phrase:u64, target:u64) -> i64 {
    if !phrase || !target { return 0 }
    let prototype = context:phrase:prototype(state, phrase)
    let base = context:phrase:prototype(state, target)
    return phrase == target || prototype == target || (base && (phrase == base || prototype == base))
}

let Shell:Completion:introducer = fn (state:Context*, phrase:u64) -> i64 {
    let shell = context:phrase:find(state, "Shell")
    return Shell:Completion:alias(state, phrase, context:phrase:find(state, "run")) ||
           Shell:Completion:alias(state, phrase, context:phrase:find(state, "capture")) ||
           Shell:Completion:alias(state, phrase, context:phrase:find(state, "spawn")) ||
           Shell:Completion:alias(state, phrase, context:phrase:find:exact(state, shell, "explicit_form"))
}

// Modes: 0 statement start; 1 RecurLoop expression; 2 Shell word grammar.
// This is a non-executing prefix walk. It never calls the input's phrase actions.
let Shell:Completion:scan = fn (state:Context*) -> Shell:Completion:Input* {
    let input = alloc(Shell:Completion:Input)
    if !input { return cast(Shell:Completion:Input*, 0) }
    input.token = Shell:Text:new()
    if !input.token || !input.token.reserve(0) {
        Shell:Text:destroy(input.token)
        free(cast(u8*, input))
        return cast(Shell:Completion:Input*, 0)
    }
    input.opening = 0
    input.files = 0
    input.commands = 0
    input.phrases = 0
    input.implicit = 0
    input.words = cast(Shell:Command*, 0)
    input.command_start = 0
    Shell:Completion:new_command(input)
    Shell:Completion:reset(input, 0)
    let count = context:completion:dictionary:count(state)
    input.root = context:completion:dictionary(state, count - 1)
    let current = context:completion:dictionary(state, 0)
    let root_lookup = !current || current == input.root
    let shell = context:phrase:find(state, "Shell")
    let grammar = context:phrase:find:exact(state, shell, "Grammar")
    let command_grammar = context:phrase:find:exact(state, grammar, "command")
    let implicit = root_lookup && !context:phrase:find(state, "Amber")
    let source = context:completion:source(state)
    let cursor = context:completion:cursor(state)
    var mode = 1
    if root_lookup { mode = 0 }
    if current == command_grammar { mode = 2 }
    var command = 1
    var redirect = 0
    var expression_start = 0
    var statement_token = 0
    var interpolation = 0
    var shell_quote:u8 = 0
    var interpolated_word = 0
    var comment = 0
    var index:u64 = 0
    while index < cursor {
        let byte = source[index]
        var handled = 0
        if comment == 1 {
            handled = 1
            if byte == 10 {
                comment = 0
                mode = 0
                command = 1
                Shell:Completion:new_command(input)
                input.command_start = index + 1
                Shell:Completion:reset(input, index + 1)
            }
        } else if comment == 2 {
            handled = 1
            if byte == 42 && index + 1 < cursor && source[index + 1] == 47 {
                comment = 0
                index += 1
                Shell:Completion:reset(input, index + 1)
            }
        } else if input.escaped {
            input.token.append_byte(byte)
            input.escaped = 0
            handled = 1
        } else if byte == 92 {
            input.escaped = 1
            handled = 1
        } else if input.quote && !(mode == 2 && input.quote == 34 && byte == 123) {
            if byte == input.quote { input.quote = 0 }
            else { input.token.append_byte(byte) }
            handled = 1
        }
        if !handled && mode == 0 {
            if Completion:space(byte) || byte == 123 || byte == 125 {
                Shell:Completion:reset(input, index + 1)
                handled = 1
            } else {
                let matched = context:phrase:probe:longest(state, current, &source[index], cursor - index)
                var length:u64 = 0
                if matched { length = context:phrase:key(state, matched, cast(u8*, 0), 0) }
                if length && Shell:Completion:introducer(state, matched) {
                    mode = 2
                    index += length - 1
                    command = 1
                    statement_token = 0
                    Shell:Completion:reset(input, index + 1)
                    input.command_start = index + 1
                    handled = 1
                    // `shell { ... }` selects a block, rather than starting a
                    // command interpolation. Each statement still uses lookup.
                    let explicit = context:phrase:find:exact(state, shell, "explicit_form")
                    if Shell:Completion:alias(state, matched, explicit) {
                        var next = index + 1
                        while next < cursor && Completion:space(source[next]) { next += 1 }
                        if next < cursor && source[next] == 123 {
                            index = next
                            mode = 0
                            input.command_start = index + 1
                            Shell:Completion:reset(input, index + 1)
                        }
                    }
                } else {
                    mode = 1
                    if implicit && !length { mode = 2 }
                    statement_token = 1
                }
            }
        }
        if !handled && mode == 1 && byte == 47 && index + 1 < cursor {
            if source[index + 1] == 47 || source[index + 1] == 42 {
                comment = 1
                if source[index + 1] == 42 { comment = 2 }
                index += 1
                handled = 1
            }
        }
        if !handled && mode == 1 && expression_start && !Completion:space(byte) {
            let matched = context:phrase:probe:longest(state, input.root, &source[index], cursor - index)
            var length:u64 = 0
            if matched { length = context:phrase:key(state, matched, cast(u8*, 0), 0) }
            if !interpolation && length && Shell:Completion:introducer(state, matched) {
                mode = 2
                command = 1
                redirect = 0
                index += length - 1
                Shell:Completion:reset(input, index + 1)
                input.command_start = index + 1
                handled = 1
            }
            expression_start = 0
        }
        if !handled {
            if byte == 34 || byte == 39 {
                input.quote = byte
            } else if mode == 2 && byte == 123 {
                input.programmable = 0
                shell_quote = input.quote
                mode = 1
                interpolation = 1
                interpolated_word = 1
                statement_token = 0
                Shell:Completion:reset(input, index + 1)
            } else if mode == 1 && interpolation && byte == 125 {
                interpolation -= 1
                Shell:Completion:reset(input, index + 1)
                if interpolation == 0 { mode = 2; input.quote = shell_quote }
            } else if mode == 1 && interpolation && byte == 123 {
                interpolation += 1
                Shell:Completion:reset(input, index + 1)
            } else if (!interpolation && (byte == 10 || byte == 13)) ||
                      (mode == 1 && !interpolation && (byte == 123 || byte == 125 || byte == 59)) {
                mode = 0
                command = 1
                redirect = 0
                statement_token = 0
                Shell:Completion:new_command(input)
                input.command_start = index + 1
                Shell:Completion:reset(input, index + 1)
            } else if mode == 2 && (byte == 124 || byte == 59 || byte == 62 || byte == 38) {
                var size:u64 = 1
                if index + 1 < cursor && source[index + 1] == byte { size = 2 }
                let spelling = Shell:copy_slice(source, cast(i64, index), cast(i64, index + size))
                var selected_operator = context:phrase:find:exact(state, command_grammar, spelling)
                free(spelling)
                if !selected_operator && size == 2 {
                    size = 1
                    let single = Shell:copy_slice(source, cast(i64, index), cast(i64, index + 1))
                    selected_operator = context:phrase:find:exact(state, command_grammar, single)
                    free(single)
                }
                if selected_operator {
                    if byte == 62 { redirect = 1; input.programmable = 0 }
                    else {
                        command = 1
                        redirect = 0
                        Shell:Completion:new_command(input)
                        input.command_start = index + size
                    }
                    index += size - 1
                    statement_token = 0
                    interpolated_word = 0
                    Shell:Completion:reset(input, index + 1)
                } else {
                    input.token.append_byte(byte)
                }
            } else if Completion:space(byte) {
                if input.token.length || input.start < index || interpolated_word {
                    if mode == 2 {
                        if input.words && !input.words.add(input.token.data) { input.programmable = 0 }
                        if redirect { redirect = 0 }
                        else { command = 0 }
                    }
                    statement_token = 0
                }
                if mode == 2 { interpolated_word = 0 }
                Shell:Completion:reset(input, index + 1)
            } else if mode == 1 && Completion:separator(byte) {
                expression_start = byte == 61 || byte == 40
                statement_token = 0
                Shell:Completion:reset(input, index + 1)
            } else {
                input.token.append_byte(byte)
            }
        }
        index += 1
    }
    input.files = mode == 2
    input.commands = input.files && command && !redirect
    input.phrases = 1
    input.implicit = mode == 0 || statement_token
    if implicit && input.implicit { input.commands = 1 }
    if input.quote && mode != 2 { input.commands = 0; input.phrases = 0 }
    if comment || input.escaped { input.files = 0; input.commands = 0; input.phrases = 0 }
    if mode == 2 && interpolated_word { input.files = 0; input.commands = 0 }
    if input.start < cursor && (source[input.start] == 34 || source[input.start] == 39) {
        input.opening = source[input.start]
        if input.quote != input.opening { input.files = 0; input.commands = 0; input.phrases = 0 }
    }
    // Avoid replacing the quoted tail of a word with an unquoted full path.
    var raw = input.start
    while raw < cursor {
        if !input.opening && (source[raw] == 34 || source[raw] == 39) {
            input.files = 0
            input.commands = 0
            input.phrases = 0
        }
        raw += 1
    }
    return input
}

let Shell:Completion:escape = fn (byte:u8, quote:u8) -> i64 {
    if quote { return byte == quote || byte == 92 || (quote == 34 && byte == 123) }
    return Completion:space(byte) || byte == 92 || byte == 34 || byte == 39 ||
           byte == 124 || byte == 59 || byte == 38 || byte == 60 || byte == 62 ||
           byte == 40 || byte == 41 || byte == 123 || byte == 125 || byte == 91 ||
           byte == 93 || byte == 36 || byte == 96 || byte == 42 || byte == 63 || byte == 33
}

let Shell:Completion:add_candidate = fn (state:Context*, input:Shell:Completion:Input*, candidate:u8*) -> i64 {
    if !Completion:starts(candidate, input.token.data) { return 0 }
    if input.commands && input.implicit && !input.quote {
        let matched = context:phrase:probe:longest(state, input.root, candidate, Completion:length(candidate))
        if matched && context:phrase:key(state, matched, cast(u8*, 0), 0) { return 0 }
    }
    let encoded = Shell:Text:new()
    if !encoded { return 0 }
    defer Shell:Text:destroy(encoded)
    if input.opening { encoded.append_byte(input.opening) }
    var index = 0
    while candidate[index] {
        let byte = candidate[index]
        if byte < 32 || byte == 127 { return 0 }
        if Shell:Completion:escape(byte, input.quote) { encoded.append_byte(92) }
        if !encoded.append_byte(byte) { return 0 }
        index += 1
    }
    return cast(i64, context:completion:add(state, encoded.data))
}

let Shell:Completion:candidate = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let input = cast(Shell:Completion:Input*, context:completion:data(state))
        if !input { return }
        Shell:Completion:add_candidate(state, input, context:completion:candidate(state))
    }
}

// Ask installed Bash completion functions about the current command only.
// Decoded words travel as argv; the edited command is never executed or eval'd.
let Shell:Completion:bash = fn (state:Context*, input:Shell:Completion:Input*) -> i64 {
    if !input.words { return 0 }
    let script = "exec 2>/dev/null
for file in /usr/share/bash-completion/bash_completion /etc/bash_completion /usr/local/share/bash-completion/bash_completion; do
    if [[ -r $file ]]; then source \"$file\" >/dev/null; break; fi
done
COMP_LINE=\"$1\"
shift
COMP_WORDS=(\"$@\")
COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
COMP_TYPE=9
COMP_KEY=9
COMP_WORDBREAKS=$' \\t\\n\"\\'><=;|&(:'
COMP_POINT=${#COMP_LINE}
if ((COMP_CWORD == 0)); then compgen -c -- \"${COMP_WORDS[0]}\"; exit 0; fi
command=${COMP_WORDS[0]}
current=${COMP_WORDS[COMP_CWORD]}
previous=${COMP_WORDS[COMP_CWORD-1]}
if ! specification=$(complete -p -- \"$command\"); then
    if declare -F _comp_load >/dev/null; then _comp_load \"$command\" >/dev/null
    elif declare -F _completion_loader >/dev/null; then _completion_loader \"$command\" >/dev/null
    fi
    specification=$(complete -p -- \"$command\") || exit 0
fi
# Only the trusted completion registration is interpreted. Input words remain argv.
eval \"options=($specification)\"
options=(\"${options[@]:1:${#options[@]}-2}\")
# Readline normally marks directories for filename completions. Capture the
# registration and dynamic compopt changes when invoking functions directly.
filenames=0
compopt() {
    local mode=1 option
    while (($#)); do
        case $1 in
            -o|+o)
                [[ $1 == -o ]] && mode=1 || mode=0
                shift
                option=${1-}
                [[ $option == filenames || $option == dirnames ]] && filenames=$mode
                ;;
        esac
        (($#)) && shift
    done
    return 0
}
emit_candidates() {
    local candidate
    for candidate in \"$@\"; do
        if ((filenames)) && [[ $candidate != */ && -d $candidate ]]; then candidate+=/; fi
        printf '%s\\n' \"$candidate\"
    done
}
for ((index=0; index<${#options[@]}; index++)); do
    if [[ ${options[index]} == -o ]]; then compopt -o \"${options[index+1]}\"; fi
    if [[ ${options[index]} == -f || ${options[index]} == -d ]]; then filenames=1; fi
    if [[ ${options[index]} == -A && ( ${options[index+1]} == file || ${options[index+1]} == directory ) ]]; then filenames=1; fi
done
for ((index=0; index<${#options[@]}; index++)); do
    if [[ ${options[index]} == -F ]]; then
        function=${options[index+1]}
        COMPREPLY=()
        \"$function\" \"$command\" \"$current\" \"$previous\" >/dev/null
        if ((${#COMPREPLY[@]})); then emit_candidates \"${COMPREPLY[@]}\"; fi
        exit 0
    fi
done
mapfile -t COMPREPLY < <(compgen \"${options[@]}\" -- \"$current\")
if ((${#COMPREPLY[@]})); then emit_candidates \"${COMPREPLY[@]}\"; fi
exit 0
"
    let pipeline = Shell:Pipeline:new()
    if !pipeline { return 0 }
    defer Shell:Pipeline:destroy(pipeline)
    let command = Shell:Command:new()
    if !command { return 0 }
    if !pipeline.add(command) { command.destroy(); return 0 }
    if !command.add("bash") || !command.add("--noprofile") || !command.add("--norc") ||
       !command.add("-c") || !command.add(script) || !command.add("recurloop-completion") { return 0 }
    let line = Completion:copy(state, context:completion:source(state), input.command_start, context:completion:cursor(state))
    if !line { return 0 }
    defer context:memory:release(state, line)
    if !command.add(line) { return 0 }
    var index:i64 = 0
    while index < input.words.argc {
        if !command.add(input.words.argv[index]) { return 0 }
        index += 1
    }
    if !command.add(input.token.data) { return 0 }
    let result = Shell:capture_pipeline(pipeline)
    if !result { return 0 }
    defer Shell:Capture:destroy(result)
    if result.exit_code || !result.output { return 0 }
    var count:i64 = 0
    var begin:i64 = 0
    index = 0
    while result.output[index] {
        if result.output[index] == 10 {
            result.output[index] = 0
            count += Shell:Completion:add_candidate(state, input, &result.output[begin])
            begin = index + 1
        }
        index += 1
    }
    if begin < index { count += Shell:Completion:add_candidate(state, input, &result.output[begin]) }
    return count
}

let Shell:Completion:complete = phrase {
    type = <phrase-types:elaborate>
    action = fn (state:Context*, called:Phrase*) -> void {
        let input = Shell:Completion:scan(state)
        if !input { return }
        defer free(cast(u8*, input))
        defer Shell:Text:destroy(input.token)
        defer Shell:Command:destroy(input.words)
        let previous = context:completion:data(state)
        context:completion:data(state, cast(u64, input))
        defer context:completion:data(state, previous)
        context:completion:start(state, input.start)
        var slash = 0
        var index = 0
        while input.token.data[index] {
            if input.token.data[index] == 47 { slash = 1 }
            index += 1
        }
        let consumer = context:phrase:find(state, "Shell")
        let owner = context:phrase:find:exact(state, consumer, "Completion")
        let callback = context:phrase:find:exact(state, owner, "candidate")
        var programmable = 0
        if (input.files || input.commands) && input.programmable && (!input.commands || !slash) {
            programmable = Shell:Completion:bash(state, input)
        }
        if !programmable && input.files && (!input.commands || slash) {
            context:completion:paths(state, input.token.data, input.commands, callback)
        }
        if input.commands && !slash { context:completion:programs(state, input.token.data, callback) }
        if input.phrases && !input.quote && !slash { Completion:phrases(state, input.start) }
    }
}

// Libraries publish behavior by rebinding the generic service slot. A caller
// can restore the default with `let Completion:complete = <Completion:lexicon>`.
let Completion:complete = <Shell:Completion:complete>
