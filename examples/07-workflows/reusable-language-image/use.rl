// Run with:
//   build/Debug/bin/recurloop --import /tmp/recurloop-phrase-language.rli \
//     --file examples/07-workflows/reusable-language-image/use.rl

var answer = 0
repeat 3 {
    answer += 14
}

assert answer == 42
assert verify_phrase_pair() == 42
announce_phrase_language
