// Short editor contracts. Ordinary dictionaries remain editable by libraries.
let RecurLoopHelp = phrase { dictionary = true permanent = true }

let RecurLoopHelp:let = [
    pattern = phrase { payload = "<name:qualified-id> = <definition:raw>" }
    snippet = phrase { payload = "${phrase} ${1:name} = phrase { docs = \"${2:Description.}\" }" }
    example = phrase { payload = "let say = <print>" }
    summary = phrase { payload = "Define a function, alias, dictionary or phrase." }
    tags = phrase { payload = "define function alias language dictionary" }
    arguments = [
        name = phrase { dictionary = true docs = "New name; qualify it with a dictionary, e.g. Tools:say." }
        definition = phrase { dictionary = true docs = "fn, phrase, a reference <name> or a dictionary [...]. Inside fn, let also binds expression values." }
    ]
]
set let.help = <RecurLoopHelp:let>

let RecurLoopHelp:var = [
    pattern = phrase { payload = "<name:id> [\":\" <type:qualified-id>] \"=\" <value:expr>" }
    snippet = phrase { payload = "${phrase} ${1:name} = ${2:0}" }
    example = phrase { payload = "var count = 0\ncount += 1" }
    summary = phrase { payload = "Create a mutable value." }
    tags = phrase { payload = "variable mutable counter" }
    arguments = [
        name = phrase { dictionary = true docs = "Name of the new variable." }
        type = phrase { dictionary = true docs = "Optional native type; inferred when omitted." }
        value = phrase { dictionary = true docs = "Initial value. Assignment may change it later." }
    ]
]
set var.help = <RecurLoopHelp:var>

let RecurLoopHelp:const = [
    pattern = phrase { payload = "<name:id> [\":\" <type:qualified-id>] \"=\" <value:expr>" }
    snippet = phrase { payload = "${phrase} ${1:name} = ${2:42}" }
    example = phrase { payload = "const limit = 42" }
    summary = phrase { payload = "Create a constant." }
    tags = phrase { payload = "constant immutable value" }
    arguments = [
        value = phrase { dictionary = true docs = "Constant expression; the value cannot be reassigned." }
        type = phrase { dictionary = true docs = "Optional native type." }
    ]
]
set const.help = <RecurLoopHelp:const>

let RecurLoopHelp:fn = [
    pattern = phrase { payload = "[<name:id>] \"(\" <parameters:raw> \")\" \"->\" <result:qualified-id> [<body:block>]" }
    snippet = phrase { payload = "${phrase} ${1:name}(${2}) -> ${3:void} {\n\t${0}\n}" }
    example = phrase { payload = "fn add(a:i64, b:i64) -> i64 { return a + b }" }
    summary = phrase { payload = "Compile a typed function." }
    tags = phrase { payload = "function parameters return native" }
    arguments = [
        parameters = phrase { dictionary = true docs = "Comma-separated name:type pairs; leave empty for no parameters." }
        result = phrase { dictionary = true docs = "Return type; use void when no value is returned." }
        body = phrase { dictionary = true docs = "Statements in braces. return supplies the result." }
    ]
]
set fn.help = <RecurLoopHelp:fn>

let RecurLoopHelp:record = [
    pattern = phrase { payload = "<name:id> <fields:block>" }
    snippet = phrase { payload = "${phrase} ${1:Name} { ${2:field}:${3:i64} }" }
    example = phrase { payload = "record Point { x:i64 y:i64 }" }
    summary = phrase { payload = "Define a native record." }
    tags = phrase { payload = "type struct record fields" }
    arguments = [
        name = phrase { dictionary = true docs = "Name of the new type." }
        fields = phrase { dictionary = true docs = "Fields as name:type pairs. Layout and alignment are calculated." }
    ]
]
set record.help = <RecurLoopHelp:record>

let RecurLoopHelp:if = [
    pattern = phrase { payload = "<condition:expr> <accepted:block> [else <rejected:block>]" }
    snippet = phrase { payload = "${phrase} ${1:condition} {\n\t${0}\n}" }
    example = phrase { payload = "if count > 0 { print count }" }
    summary = phrase { payload = "Execute a block when its condition is true." }
    tags = phrase { payload = "condition branch optional else" }
    arguments = [
        condition = phrase { dictionary = true docs = "An expression interpreted as true or false." }
        accepted = phrase { dictionary = true docs = "Code executed when the condition is true." }
        rejected = phrase { dictionary = true docs = "Optional else block executed when the condition is false." }
    ]
]
set if.help = <RecurLoopHelp:if>

let RecurLoopHelp:while = [
    pattern = phrase { payload = "<condition:expr> <body:block>" }
    snippet = phrase { payload = "${phrase} ${1:condition} {\n\t${0}\n}" }
    example = phrase { payload = "while count < 3 { count += 1 }" }
    summary = phrase { payload = "Repeat while the condition is true." }
    tags = phrase { payload = "loop repeat iteration" }
    arguments = [
        condition = phrase { dictionary = true docs = "Checked before each iteration." }
        body = phrase { dictionary = true docs = "Update the condition or use break to end the loop." }
    ]
]
set while.help = <RecurLoopHelp:while>

let RecurLoopHelp:include = [
    pattern = phrase { payload = "<path:string>" }
    snippet = phrase { payload = "${phrase} \"${1:file.rl}\"" }
    example = phrase { payload = "include \"helpers.rl\"" }
    summary = phrase { payload = "Execute a source file here." }
    tags = phrase { payload = "import source file library" }
    arguments = [
        path = phrase { dictionary = true docs = "Quoted path, relative to the including file." }
    ]
]
set include.help = <RecurLoopHelp:include>

let RecurLoopHelp:print = [
    pattern = phrase { payload = "<value:expr>" }
    snippet = phrase { payload = "${phrase} ${1:value}" }
    example = phrase { payload = "print 20 + 22" }
    summary = phrase { payload = "Print a value followed by a newline." }
    tags = phrase { payload = "output console text" }
    arguments = [
        value = phrase { dictionary = true docs = "An expression to display." }
    ]
]
set print.help = <RecurLoopHelp:print>

let RecurLoopHelp:assert = [
    pattern = phrase { payload = "<condition:expr>" }
    snippet = phrase { payload = "${phrase} ${1:condition}" }
    example = phrase { payload = "assert 20 + 22 == 42" }
    summary = phrase { payload = "Fail when the condition is false." }
    tags = phrase { payload = "check test assertion" }
    arguments = [
        condition = phrase { dictionary = true docs = "True means success; false stops execution with a diagnostic." }
    ]
]
set assert.help = <RecurLoopHelp:assert>

let RecurLoopHelp:link = [
    pattern = phrase { payload = "((shared | object | archive | path | library) <path:string> | clear)" }
    snippet = phrase { payload = "${phrase} ${1|shared,object,archive,path,library|} \"${2:name}\"" }
    example = phrase { payload = "link shared \"c\"" }
    summary = phrase { payload = "Configure native linker inputs." }
    tags = phrase { payload = "native library linking external" }
    arguments = [
        path = phrase { dictionary = true docs = "Library name for shared/library; filesystem path for object/archive/path." }
    ]
]
set link.help = <RecurLoopHelp:link>

let RecurLoopHelp:module = [
    pattern = phrase { payload = "(auto | manual | clear | embed | strip | (include | exclude | dynamic | entry) <symbol:qualified-id>)" }
    snippet = phrase { payload = "${phrase} ${1|auto,manual,clear,embed,strip,include,exclude,dynamic,entry|} ${0}" }
    example = phrase { payload = "module entry app_main" }
    summary = phrase { payload = "Select native output modules and entry point." }
    tags = phrase { payload = "native modules entry output" }
    arguments = [
        symbol = phrase { dictionary = true docs = "A native function or module name." }
    ]
]
set module.help = <RecurLoopHelp:module>

let RecurLoopHelp:engine = [
    pattern = phrase { payload = "(import | export) <path:string>" }
    snippet = phrase { payload = "${phrase} ${1|import,export|} \"${2:language.rli}\"" }
    example = phrase { payload = "engine export \"language.rli\"" }
    summary = phrase { payload = "Load or save the language image." }
    tags = phrase { payload = "language persist image import export" }
    arguments = [
        path = phrase { dictionary = true docs = "An engine image (.rli). Export keeps phrases, docs and help." }
    ]
]
set engine.help = <RecurLoopHelp:engine>

let RecurLoopHelp:emit = [
    pattern = phrase { payload = "(executable [debug] | object | raw) <path:string> <definition:raw>" }
    snippet = phrase { payload = "${phrase} executable \"${1:app}\" ${2:app_main} = fn () -> i64 {\n\treturn ${3:0}\n}" }
    example = phrase { payload = "emit executable \"app\" app_main = fn () -> i64 { return 0 }" }
    summary = phrase { payload = "Write native code or exact bytes." }
    tags = phrase { payload = "build output executable binary object" }
    arguments = [
        path = phrase { dictionary = true docs = "Destination file." }
        definition = phrase { dictionary = true docs = "name = fn (...) -> type {...}; raw uses = hex {...}." }
    ]
]
set emit.help = <RecurLoopHelp:emit>

let RecurLoopHelp:syntax = [
    pattern = phrase { payload = "[(extend | replace)] <name:id> <definition:rest>" }
    snippet = phrase { payload = "${phrase} ${1:unless} <condition:expr> <body:block> => if !(\\${condition}) \\${body}" }
    example = phrase { payload = "syntax unless <condition:expr> <body:block> => if !(${condition}) ${body}" }
    summary = phrase { payload = "Define a phrase pattern and its behavior." }
    tags = phrase { payload = "language grammar syntax rewrite custom" }
    arguments = [
        name = phrase { dictionary = true docs = "New phrase name; extend preserves the previous syntax as fallback." }
        definition = phrase { dictionary = true docs = "Captures <name:matcher>, [optional], (a | b); finish with => replacement, as <phrase> or action fn." }
    ]
]
set syntax.help = <RecurLoopHelp:syntax>

// Explicit selectors, rather than assumptions in the editor.
let RecurLoopHelp:fn:arguments:result:kind = phrase { payload = "type" }
let RecurLoopHelp:var:arguments:type:kind = phrase { payload = "type" }
let RecurLoopHelp:const:arguments:type:kind = phrase { payload = "type" }
let RecurLoopHelp:module:arguments:symbol:kind = phrase { payload = "function" }
