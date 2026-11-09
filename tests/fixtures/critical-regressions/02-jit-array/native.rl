link shared "c"
extern free(pointer:u8*) -> void abi sysv-amd64
record Table { values:i64[64] total:i64 }
let f = fn (n:i64) -> i64 {
  let x = alloc(Table)
  if !x { return -1 }
  var i:i64 = 0
  x.total = 0
  while i < 64 { x.values[i] = 0 i += 1 }
  i = 0
  while i < n {
    let t = i % 64
    x.values[t] += 1
    i += 1
  }
  i = 0
  while i < 64 { x.total += x.values[i] i += 1 }
  let sum = x.total
  return sum
}


link shared "c"
extern printf(format:u8*, ...) -> i32 abi sysv-amd64
module auto
emit executable "./build/array-aggregation-native" main = fn () -> i64 {
  let value = f(100)
  printf("%ld\n", value)
  if value != 100 { return 1 }
  return 0
}
