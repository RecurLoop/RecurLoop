#include <gtest/gtest.h>
#include <recurloop/Recurloop.hpp>
#include <recurloop/SyntaxPattern.hpp>
#include <algorithm>

TEST(SyntaxExpectations, ChoicesAndOptionalPartsKeepEveryViableContinuation) {
  const auto expected = recurloop::SyntaxPattern::expect("[quiet] (fast | safe) <value:number>", "");
  std::vector<std::string> literals;
  for (const auto &item : expected) literals.push_back(item.literal);
  EXPECT_EQ(literals, (std::vector<std::string>{"fast", "quiet", "safe"}));
  const auto partial = recurloop::SyntaxPattern::expect("(fast | safe) <value:number>", "sa");
  ASSERT_EQ(partial.size(), 1);
  EXPECT_EQ(partial.front().literal, "safe");
  EXPECT_TRUE(recurloop::SyntaxPattern::expect("(fast | safe) <value:number>", "slow").empty());
}

TEST(SyntaxExpectations, CapturesRespectBalancedExpressionsAndCompletedLines) {
  const auto expected = recurloop::SyntaxPattern::expect("<condition:expr> then <body:block>", "(a + b) th");
  EXPECT_TRUE(std::ranges::any_of(expected, [](const auto &item) { return item.literal == "then" && item.start == 8; }));
  const auto slot = recurloop::SyntaxPattern::expect("<value:qualified-id>", "Tools:va");
  ASSERT_EQ(slot.size(), 2);
  EXPECT_EQ(slot.front().name, "value");
  EXPECT_EQ(slot.front().start, 0);
  EXPECT_TRUE(recurloop::SyntaxPattern::expect("<value:expr>", "42\nother").empty());
  EXPECT_ANY_THROW(recurloop::SyntaxPattern::validate("<value:unknown>"));
  const auto finished = recurloop::SyntaxPattern::expect("<body:block> [else <other:block>]", "{}\n");
  EXPECT_TRUE(std::ranges::any_of(finished, [](const auto &item) { return item.matcher.empty() && item.literal.empty(); }));
  EXPECT_TRUE(std::ranges::any_of(finished, [](const auto &item) { return item.literal == "else"; }));
}

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
