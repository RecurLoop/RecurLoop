// Conditional lists use pipeline status and equal, left-associative precedence.
run true && echo and-ok
assert status == 0
run false && echo should-not-run
assert status == 1
run false || echo or-ok
assert status == 0
run true || echo should-not-run
assert status == 0
run false && echo should-not-run || echo recovered
run true || echo should-not-run && echo left-to-right
run false | cat && echo should-not-run || echo pipefail
run echo 'literal && || ;' && echo escaped\&\&word
capture printf first && printf second
assert captured == "firstsecond"
run sh -c 'exit 7' && echo should-not-run
assert status == 7
run false; echo sequence
run true&&echo no-spaces
run false||echo no-spaces-or
run echo trailing-semicolon;
