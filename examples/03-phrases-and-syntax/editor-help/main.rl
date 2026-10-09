// The editor reads this help from the language, including custom dictionaries.
let Values = []
var Values:answer = 42
var Values:greeting = "hello"

syntax show <value:id> => print Values:${value}
let ShowHelp = [
    summary = phrase { payload = "Print a named value." }
    snippet = phrase { payload = "${phrase} ${1:answer}" }
    example = phrase { payload = "show answer" }
    tags = phrase { payload = "display output values" }
    arguments = [
        value = phrase { dictionary = true docs = "A name in Values; choose answer or greeting." }
    ]
]
let ShowHelp:arguments:value:dictionary = <Values>
set show.docs = "Prints the selected value from Values."
set show.help = <ShowHelp>

// No pattern is repeated: `syntax` already owns it. Aliases inherit the help.
let display = <show>
show answer
display greeting
