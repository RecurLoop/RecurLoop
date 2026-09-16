#include <gtest/gtest.h>
#include <recurloop/Recurloop.hpp>

class SyntaxPatternTesting : public recurloop::Recurloop, public testing::Test {
public:
  int execute(int argc, char **argv) {
    return Recurloop::initialize(argc, argv).execute();
  }
};

TEST_F(SyntaxPatternTesting, DeclarativeRewriteWorksAtTopLevelAndInsideFunctions) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax unless <condition:expr> <body:block> => if !(${condition}) ${body}

var value = 0
unless 1 == 0 {
  value = 41
}
assert value == 41

let answer = fn () -> i64 {
  unless 1 == 0 {
    return 42
  }
  return 0
}
assert answer() == 42
)RL"};

  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, ReplaceCanReusePreviousSemanticsThroughAliasMode) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax replace if "(" <condition:expr> ")" <accepted:block> [else <rejected:block>] as <if>

var value = 0
if (1 == 1) {
  value = 7
} else {
  value = 9
}
assert value == 7

let answer = fn () -> i64 {
  if (1 == 1) {
    return 42
  } else {
    return 0
  }
}
assert answer() == 42
)RL"};

  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, ExtendKeepsPreviousSyntaxAsFallback) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax extend if "(" <condition:expr> ")" <accepted:block> [else <rejected:block>] as <if>

var plain = 0
if 1 == 1 {
  plain = 1
}
assert plain == 1

var parenthesized = 0
if (1 == 1) {
  parenthesized = 2
}
assert parenthesized == 2

let answer = fn (flag:i64) -> i64 {
  if flag {
    if (flag == 1) {
      return 42
    }
  }
  return 0
}
assert answer(1) == 42
)RL"};

  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, InlineActionCanReadCapturesDuringFunctionRewrite) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax literal <value:number> action fn (state:Context*, called:Phrase*) -> void {
  if !context:syntax:active(state) {
    context:diagnostic:error(state, "literal syntax is only valid inside fn")
    return
  }
  if !context:syntax:capture:exists(state, "value") {
    context:diagnostic:error(state, "literal syntax lost its value capture")
    return
  }
  context:syntax:emit(state, context:syntax:capture(state, "value"))
}

let answer = fn () -> i64 {
  return literal 42
}
assert answer() == 42
)RL"};

  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}
