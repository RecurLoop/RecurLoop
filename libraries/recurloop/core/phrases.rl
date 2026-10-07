// Fundamental phrase graph and phrase kinds. The five phrase-type records are kernel contracts, not binary payload dumps.

phrase root = "" in none {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor root
}

phrase phrase_types = "phrase-types" in root {
  docs "```recurloop\ntype = <phrase-types:kind>\n```\n\nContains the execution kinds `data`, `elaborate`, `callable` and `scoped-callable`."
  dictionary
  type phrase_types_data
}

phrase phrase_types_callable = "callable" in phrase_types {
  docs "```recurloop\ntype = <phrase-types:callable>\n```\n\nInvokes the phrase action when evaluated."
  type phrase_types_data
  phrase-type callable
}

phrase phrase_types_data = "data" in phrase_types {
  docs "```recurloop\ntype = <phrase-types:data>\n```\n\nStores data without invoking an action during lookup."
  type phrase_types_data
  phrase-type data
}

phrase phrase_types_elaborate = "elaborate" in phrase_types {
  docs "```recurloop\ntype = <phrase-types:elaborate>\n```\n\nRuns an action while source is being elaborated; use for language constructs."
  type phrase_types_data
  phrase-type elaborate
}

phrase phrase_types_scoped_callable = "scoped-callable" in phrase_types {
  docs "```recurloop\ntype = <phrase-types:scoped-callable>\n```\n\nInvokes an action and returns lookup to the parent dictionary."
  type phrase_types_data
  phrase-type scoped-callable
}

phrase syntax_definition = "syntax" in root {
  kind "keyword"
  color "#569CD6"
  docs "```recurloop\nsyntax name <capture:matcher> ... => replacement\n```\n\nDefines source syntax and rewrites it to ordinary RecurLoop. Refer to a capture as `${capture}`. Available matchers include `expr`, `block`, `id`, `token`, `string` and `raw`.\n\n`[ ... ]` makes a part optional; `(a | b)` selects a choice. `syntax extend` keeps the previous definition as fallback; `syntax replace` shadows it. End with `as <phrase>` to reuse semantics, or `action fn (state:Context*, called:Phrase*) -> void { ... }` for a custom parser action.\n\n**Example**\n\n```recurloop\nsyntax unless <condition:expr> <body:block> => if !(${condition}) ${body}\n```"
  type phrase_types_elaborate
  action host "syntax.define"
}
