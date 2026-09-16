// Build an engine image containing declarative syntax.  This file deliberately
// combines a rewrite rule with an extended built-in phrase so the import test
// verifies payloads, actions, prototypes and successors together.

syntax unless <condition:expr> <body:block> => if (!(${condition})) ${body}
syntax extend if "(" <condition:expr> ")" <accepted:block> [else <rejected:block>] as <if>

engine export "/tmp/recurloop-declarative-syntax.rli"
print "declarative syntax export ok"
