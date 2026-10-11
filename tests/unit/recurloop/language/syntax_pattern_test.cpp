#include <gtest/gtest.h>
#include <recurloop/Recurloop.hpp>
#include <recurloop/SyntaxPattern.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/LanguageGrammar.hpp>
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

TEST_F(SyntaxPatternTesting, CapturesPhraseDefinedBlocksGroupsAndBlockBodies) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
let begin = <{>
let end = <}>
let open = <(>
let close = <)>
syntax when <condition:expr> <body:block> => if ${condition} ${body}
syntax scoped <body:block> => if 1 == 1 { ${body.body} }
var result = 0
when open
  1 == 1
close begin
  scoped begin result = 42 end
end
assert result == 42
fn answer() -> i64 {
  when open 1 == 1 close begin
    scoped begin return 42 end
  end
  return 0
}
assert answer() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
  EXPECT_TRUE(recurloop::SyntaxPattern::accepts("block", "begin return 42 end", &getContext()));
  const auto expected = recurloop::SyntaxPattern::expect("<body:block> then", "begin end th", &getContext());
  EXPECT_TRUE(std::ranges::any_of(expected, [](const auto &item) { return item.literal == "then"; }));
}

TEST_F(SyntaxPatternTesting, CapturesLongestTokensAndSharedNumberLiteralsForNativeCompilation) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax binary <left:number> <operator:token> <right:number> => ${left} ${operator} ${right}
fn equal() -> i64 { return binary 0x2a == 42 }
fn real() -> i64 { return cast(i64, binary 1.5 + 2.5) }
assert equal() == 1
assert real() == 4
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, LongerPhrasesTakePriorityOverCommentPrefixes) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax "/*answer" <space:none> "!" => 42
syntax "//answer" <space:none> "!" => 42
fn block_prefix() -> i64 { return /*answer! }
fn line_prefix() -> i64 { return //answer! }
assert block_prefix() == 42
assert line_prefix() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST(SyntaxExpectations, RejectsMismatchedAndUnterminatedCaptureGroups) {
  EXPECT_FALSE(recurloop::SyntaxPattern::accepts("expr", "(42]"));
  EXPECT_FALSE(recurloop::SyntaxPattern::accepts("expr", "(42"));
  EXPECT_FALSE(recurloop::SyntaxPattern::accepts("block", "{ (42 }"));
}

TEST_F(SyntaxPatternTesting, LeadingLayoutCanBelongToARegisteredRewritePhrase) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax "   answer" <space:none> "!" => 42
fn layout() -> i64 { return    answer! }
assert layout() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, RegisteredQuotePrefixesPrecedeTheStringDataFallback) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax "\"answer" <space:none> "!" => 42
fn quoted_prefix() -> i64 { return "answer! }
assert quoted_prefix() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST(SyntaxExpectations, OpaqueCapturesDoNotImposeTheHostGrammar) {
  EXPECT_TRUE(recurloop::SyntaxPattern::accepts("raw", ") ] } \" /*"));
  EXPECT_TRUE(recurloop::SyntaxPattern::accepts("code", ") ] } \" /*"));
  const auto expected = recurloop::SyntaxPattern::expect("<source:code> \"|\"", ") ] } \" /* |");
  EXPECT_TRUE(
      std::ranges::any_of(expected, [](const auto &item) { return item.matcher.empty() && item.literal.empty(); }));
}

TEST_F(SyntaxPatternTesting, OpaqueSyntaxCompilesInsideSurroundingBodiesAndExpressions) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
syntax opaque <source:code> "|" => 42
syntax rawdata <source:raw> "|" => 42
syntax native_value <source:expr> "!" => ${source}
fn answer() -> i64 { return opaque ) ] } " /* | }
fn nested() -> i64 { return native_value opaque ) ] } " /* | ! }
syntax action_value "!" action fn (state:Context*, called:Phrase*) -> void {
  var result = rawdata // ) ] } " /* |
  if result != 42 { context:syntax:emit(state, "0"); return }
  context:syntax:emit(state, "42")
}
fn action_answer() -> i64 { return action_value ! }
assert answer() == 42
assert nested() == 42
assert action_answer() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, AliasReferencesReuseThePhraseNameGrammar) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
let "branch\tname" = <if>
const keyword = "branch\tname"
syntax branch <condition:expr> <body:block> as <"branch\tname">
syntax choose <condition:expr> <body:block> as <${keyword}>
var result = 0
branch 1 == 1 { result = 42 }
assert result == 42
fn answer() -> i64 {
  choose 1 == 1 { return 42 }
  return 0
}
assert answer() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, DefinitionBodiesAndMultilineTemplatesUsePhraseDelimiters) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
let begin = <{>
let end = <}>
syntax select <condition:expr> <body:block> => if ${condition} begin
  ${body.body}
end
syntax constant_value "!" action fn (state:Context*, called:Phrase*) -> void begin
  context:syntax:emit(state, "42")
end
fn answer() -> i64 begin
  select 1 == 1 begin return constant_value ! end
  return 0
end
assert answer() == 42
)RL"};
  EXPECT_EQ(execute(countof(argv), (char **)argv), 0);
}

TEST_F(SyntaxPatternTesting, BoundedBlockExtentRecognizesOpaquePhrasesWithoutExecutingThem) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
let begin = <{>
let end = <}>
syntax opaque <payload:code> "|" => 42
)RL"};
  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  auto &state = getContext();
  const auto offset = state.source.buffer.offset;
  const auto source = state.source.buffer.str;
  const std::string body = "begin let weekend = opaque } \" /* |; return weekend end trailing";
  EXPECT_EQ(recurloop::SyntaxPattern::blockExtent(state, body, 0), body.find(" trailing"));
  EXPECT_EQ(recurloop::SyntaxPattern::blockExtent(state, "begin (] end", 0), 0);
  EXPECT_EQ(recurloop::SyntaxPattern::blockExtent(state, "begin return 42", 0), 0);
  EXPECT_EQ(recurloop::SyntaxPattern::blockExtent(state, body, body.size()), 0);
  EXPECT_EQ(state.source.buffer.offset, offset);
  EXPECT_EQ(state.source.buffer.str, source);
}

TEST_F(SyntaxPatternTesting, BlockCaptureUsesAnExplicitPhraseGrammar) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
let Local = phrase { dictionary = true }
let Local:"{" = phrase { dictionary = true prototype = <"{"> }
let Local:"}" = phrase { dictionary = true prototype = <"}"> }
let Local:begin = <Local:"{">
let Local:end = <Local:"}">
let Local:"//" = phrase { dictionary = true prototype = <"//"> }
let Local:"#" = <Local:"//">
let Local:"/*" = phrase { dictionary = true prototype = <"/*"> }
let Local:"*/" = phrase { dictionary = true }
let Local:comment = <Local:"/*">
let Local:stop = <Local:"*/">
)RL"};
  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  auto &state = getContext();
  const std::string input = " header # begin\n comment begin stop begin let weekend = \"end\"; # end\n comment end "
                            "stop begin 42 end end after";
  state.source.buffer.str = input;
  state.source.buffer.offset = 0;
  state.source.buffer.bits = input.size() * Byte::length;
  state.source.more = false;
  auto grammar = recurloop::LanguageGrammar::find(state.lexicon.phrase(), "Local");
  const auto block = recurloop::Blocks::capture(state, grammar);
  EXPECT_EQ(block.header, " header # begin\n comment begin stop ");
  EXPECT_EQ(block.body, " let weekend = \"end\"; # end\n comment end stop begin 42 end ");
  EXPECT_EQ(state.source.buffer.str.substr(state.source.buffer.offset / Byte::length), " after");
}

TEST_F(SyntaxPatternTesting, CompiledPhraseDescriptionsShieldScopedSyntaxWithoutRunningActions) {
  const char *argv[] = {"Recurloop", "--string", R"RL(
let Grammar = phrase { dictionary = true }
let Grammar:"{" = phrase { dictionary = true prototype = <"{"> }
let Grammar:"}" = phrase { dictionary = true prototype = <"}"> }
let Grammar:begin = <Grammar:"{">
let Grammar:end = <Grammar:"}">
let Grammar:"//" = phrase { dictionary = true prototype = <"//"> }
let Grammar:"#" = <Grammar:"//">
let dsl = phrase {
  dictionary = true
  type = <phrase-types:elaborate>
  rewrite = true
  action = fn (state:Context*, called:Phrase*) -> void {
    context:diagnostic:error(state, "recognition invoked a phrase action")
  }
}
let alias_dsl = <dsl>
)RL"};
  ASSERT_EQ(execute(countof(argv), (char **)argv), 0);
  auto &state = getContext();
  auto phrase = recurloop::LanguageGrammar::find(state.lexicon.phrase(), "dsl");
  auto grammar = recurloop::LanguageGrammar::find(state.lexicon.phrase(), "Grammar");
  recurloop::SyntaxPattern::describe(state, phrase, "<body:block>", grammar);
  const std::string text = "{ alias_dsl begin # } \" fake root delimiters\n 42 end; return 0 } tail";
  EXPECT_EQ(recurloop::SyntaxPattern::blockExtent(state, text, 0), text.find(" tail"));
  const std::string simple = "{ alias_dsl begin 42 end }";
  EXPECT_EQ(recurloop::SyntaxPattern::blockExtent(state, simple, 0), simple.size());
}
