// Every name below is ordinary language data. The parser does not know these
// aliases; it follows the prototype chain stored in the lexicon.
let branch = <if>
let otherwise = <else>
let plus = <+>
let add = <+=>
let stringify = <str>
let done = <return>

var total = 3
total add 2
print stringify(total)

fn calculate(value:i64) -> i64 {
  branch value > 2 {
    done value plus 10
  } otherwise {
    done 1
  }
}

print stringify(calculate(3))
print stringify(calculate(1))
