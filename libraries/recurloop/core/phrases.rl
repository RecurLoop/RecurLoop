// Fundamental phrase graph and phrase kinds. The five phrase-type records are kernel contracts, not binary payload dumps.

phrase root = "" in none {
  dictionary
  type phrase_types_elaborate
  action host "lookup.enter"
  successor root
}

phrase phrase_types = "phrase-types" in root {
  dictionary
  type phrase_types_data
}

phrase phrase_types_callable = "callable" in phrase_types {
  type phrase_types_data
  phrase-type callable
}

phrase phrase_types_data = "data" in phrase_types {
  type phrase_types_data
  phrase-type data
}

phrase phrase_types_elaborate = "elaborate" in phrase_types {
  type phrase_types_data
  phrase-type elaborate
}

phrase phrase_types_scoped_callable = "scoped-callable" in phrase_types {
  type phrase_types_data
  phrase-type scoped-callable
}

phrase syntax_definition = "syntax" in root {
  type phrase_types_elaborate
  action host "syntax.define"
}
