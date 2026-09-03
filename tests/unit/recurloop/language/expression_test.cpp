#include <context/Values.hpp>
#include <compiler/LanguageState.hpp>
#include <recurloop/Recurloop.hpp>
#include <recurloop/Expressions.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <gtest/gtest.h>

#include <iterator>
#include <sstream>

namespace {
  class ValueHost : public recurloop::Recurloop {
  public:
    ValueHost() {
      char executable[] = "Recurloop";
      char *arguments[] = {executable};
      initialize(1, arguments);
    }

    context::Values values() {
      return context.values();
    }
  };
} // namespace

TEST(ValueTesting, RepresentsFormatsAndComparesLanguageValues) {
  EXPECT_EQ(context::Value(std::int64_t{42}).format(), "42");
  EXPECT_EQ(context::Value(2.5).format(), "2.5");
  EXPECT_EQ(context::Value(true).format(), "true");
  EXPECT_EQ(context::Value("text").typeName(), "string");
  EXPECT_EQ(context::Value(std::int64_t{2}), context::Value(2.0));
  EXPECT_THROW(context::Value("false").asBoolean(), Exception);
}

TEST(ValueTesting, MaintainsLexicalMutableAndConstantScopes) {
  ValueHost host;
  context::Values values = host.values();
  values.define("answer", context::Value(std::int64_t{42}));
  values.define("name", context::Value("root"), false);
  values.pushScope();
  values.define("answer", context::Value(std::int64_t{7}));
  EXPECT_EQ(values.get("answer").asInteger(), 7);
  values.assign("answer", context::Value(std::int64_t{8}));
  EXPECT_EQ(values.get("answer").asInteger(), 8);
  EXPECT_THROW(values.assign("name", context::Value("changed")), Exception);
  values.popScope();
  EXPECT_EQ(values.get("answer").asInteger(), 42);
  EXPECT_THROW(values.popScope(), Exception);
}

namespace {
  class ExpressionLanguageTesting : public recurloop::Recurloop, public testing::Test {
  protected:
    int execute(const std::string &source) {
      const char *argv[] = {"Recurloop", "--string", source.c_str()};
      initialize(static_cast<int>(std::size(argv)), const_cast<char **>(argv));
      context.io.out = &output;
      context.io.err = &errors;
      return Recurloop::execute();
    }
    std::ostringstream output;
    std::ostringstream errors;
  };
} // namespace

TEST_F(ExpressionLanguageTesting, EvaluatesArithmeticVariablesComparisonAndLogic) {
  ASSERT_EQ(execute(R"(
var total = 2 + 3 * 4
set total += 7
const limit = 21
print total
print total == limit && !(total < 20)
assert total % 4 == 1
assert 9223372036854775807 > 9223372036854775806
assert 9223372036854775807 != 9223372036854775806
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "21\ntrue\n");
  EXPECT_EQ(context.values().get("total").asInteger(), 21);
  EXPECT_THROW(context.values().assign("limit", context::Value(std::int64_t{1})), Exception);
}

TEST_F(ExpressionLanguageTesting, ContinuesTopLevelExpressionsInsidePhraseDefinedGroups) {
  ASSERT_EQ(execute(R"(
let open = <(>
let close = <)>
const answer = open
  10 +
  20 +
  12
close
assert answer == 42
)"),
            0)
      << errors.str();
}

TEST_F(ExpressionLanguageTesting, AcceptsLargeStringLiteralsWithoutALexicalLimit) {
  const std::string text(12'000, 'a');
  const std::string source = "const text = \"" + text + "\"\nassert len(text) > 10000\n";
  ASSERT_EQ(execute(source), 0) << errors.str();
  EXPECT_EQ(context.values().get("text").asString().size(), text.size());
}

TEST_F(ExpressionLanguageTesting, UsesOnePhraseGrammarForVariableConstantAndAssignmentNames) {
  ASSERT_EQ(execute(R"(
const suffix = "name"
var "spaced ${suffix}" = 40
set 'spaced ${suffix}' += 2
const namespace:item = value("spaced name")
var escaped\ name = value("namespace:item")
set escaped\ name *= 2
print value("spaced name")
print value("namespace:item")
print value("escaped name")
)"),
            0)
      << errors.str();

  EXPECT_EQ(output.str(), "42\n42\n84\n");
  EXPECT_EQ(context.values().get("spaced name").asInteger(), 42);
  EXPECT_EQ(context.values().get("namespace:item").asInteger(), 42);
  EXPECT_EQ(context.values().get("escaped name").asInteger(), 84);
}

TEST_F(ExpressionLanguageTesting, StoresBindingsAndCompilerRegistriesAsPhrases) {
  ASSERT_EQ(execute("var answer = 41\nset answer += 1\nconst name = \"phrase\"\n"), 0) << errors.str();

  const auto child = [](lexicon::Phrase dictionary, std::string_view name) {
    lexicon::Match match = dictionary.matchExact(
        Byte(const_cast<char *>(name.data())), 0, name.size() * Byte::length,
        [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
    return match.isNull() ? lexicon::Phrase(dictionary.getLexicon()) : match.getPhrase();
  };

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase values = child(root, std::string_view("\0runtime-values", 15));
  lexicon::Phrase global = child(child(values, "scopes"), "global");
  EXPECT_FALSE(child(global, "answer").isNull());
  EXPECT_FALSE(child(global, "name").isNull());

  lexicon::Phrase language = child(root, std::string_view("\0compiler-language", 18));
  ASSERT_EQ(language.payloadSize(), sizeof(compiler::Language));
  compiler::Language languageData;
  language.fetch(0, languageData);
  EXPECT_EQ(languageData.magic, compiler::Language::Magic);
  EXPECT_EQ(languageData.version, compiler::Language::Version);
  EXPECT_FALSE(child(child(language, "types"), "i64").isNull());
  EXPECT_FALSE(child(child(language, "calling-conventions"), "sysv-amd64").isNull());

  for (std::string_view name : {"var", "const", "set", "let", "emit", "asm"}) {
    lexicon::Phrase phrase = child(root, name);
    if (phrase.payloadSize() < sizeof(compiler::LanguageBinding))
      phrase = child(phrase, compiler::LanguageBindingPhraseName);
    ASSERT_FALSE(phrase.isNull()) << name;
    ASSERT_GE(phrase.payloadSize(), sizeof(compiler::LanguageBinding)) << name;
    compiler::LanguageBinding binding;
    phrase.fetch(phrase.payloadSize() - sizeof(binding), binding);
    EXPECT_EQ(binding.magic, compiler::LanguageBinding::Magic) << name;
    lexicon::Phrase target(&context.lexicon, binding.language);
    target.load();
    EXPECT_EQ(target.getAddress(), language.getAddress()) << name;
  }
}

TEST_F(ExpressionLanguageTesting, ReadsArithmeticPrecedenceFromExpressionPhrases) {
  ASSERT_EQ(execute(""), 0) << errors.str();
  EXPECT_EQ(recurloop::Expressions::evaluate(context, "2 + 3 * 4").asInteger(), 14);

  const auto child = [](lexicon::Phrase dictionary, std::string_view name) {
    return dictionary
        .matchExact(Byte(const_cast<char *>(name.data())), 0, name.size() * Byte::length,
                    [](radix::Node *, radix::Match *candidate) {
                      return !lexicon::Dictionary(*candidate).getPhrase().isNull();
                    })
        .getPhrase();
  };
  lexicon::Phrase grammar = child(context.lexicon.phrase(), std::string_view("\0expressions", 12));
  lexicon::Phrase plus = child(child(grammar, "infix"), "+");
  plus.update(1, std::uint8_t{7});

  EXPECT_EQ(recurloop::Expressions::evaluate(context, "2 + 3 * 4").asInteger(), 20);
}

TEST_F(ExpressionLanguageTesting, ProvidesComposableStringOperations) {
  ASSERT_EQ(execute(R"(
const project = "Recur" + "Loop"
var message = trim("  hello world  ")
set message = upper(replace(message, "world", project))
print message + " / " + str(len(message))
print substr(message, 6, 5)
assert contains(message, "RECUR") && starts_with(message, "HELLO")
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "HELLO RECURLOOP / 15\nRECUR\n");
}

TEST_F(ExpressionLanguageTesting, RejectsInvalidTypesAndArithmeticErrors) {
  EXPECT_NE(execute("print 1 / 0\n"), 0);
  EXPECT_NE(errors.str().find("division by zero"), std::string::npos);
}

TEST_F(ExpressionLanguageTesting, ShortCircuitsLogicalExpressions) {
  ASSERT_EQ(execute("print true || 1 / 0 == 0\nprint false && missing()\n"), 0) << errors.str();
  EXPECT_EQ(output.str(), "true\nfalse\n");
}

TEST_F(ExpressionLanguageTesting, UsesACompiledFunctionInCompoundAssignment) {
  ASSERT_EQ(execute(R"(
let next = fn () -> i64 {
  return 2
}
var value = 3
set value *= next()
print value
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "6\n");
}

TEST_F(ExpressionLanguageTesting, AssignsMutableValuesWithoutASetKeyword) {
  ASSERT_EQ(execute(R"(
var value = 6
value *= 7
let increment = fn (number:i64) -> i64 {
  number += 1
  return number
}
print value
print increment(41)
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "42\n42\n");
}

TEST_F(ExpressionLanguageTesting, ExecutesNestedConditionalBlocksWithLexicalScopes) {
  ASSERT_EQ(execute(R"(
var score = 14
if score >= 10 {
  var label = "large"
  if starts_with(label, "lar") {
    set score += 7
    print label
  } else {
    print 1 / 0
  }
} else {
  print "small"
}
print score
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "large\n21\n");
  EXPECT_FALSE(context.values().contains("label"));
}

TEST_F(ExpressionLanguageTesting, RepeatsOrdinaryRecurloopCodeWithWhile) {
  ASSERT_EQ(execute(R"(
var index = 0
var joined = ""
while index < 4 {
  set joined = joined + str(index)
  set index += 1
}
print joined
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "0123\n");
}

TEST_F(ExpressionLanguageTesting, DefinesFunctionsAsRecursiveLanguagePhrases) {
  ASSERT_EQ(execute(R"(
fn factorial(n:i64) -> i64 {
  if n <= 1 {
    return 1
  } else {
    return n * factorial(n - 1)
  }
}
var result = factorial(6)
print result
factorial(3)
)"),
            0)
      << errors.str();
  EXPECT_EQ(output.str(), "720\n");
  EXPECT_EQ(context.values().get("result").asInteger(), 720);
}

TEST_F(ExpressionLanguageTesting, NewFunctionDefinitionShadowsThePreviousOne) {
  ASSERT_EQ(execute(R"(
let calculate = fn (value:i64) -> i64 {
  return value + 1
}
var before = calculate(10)
let calculate = fn (value:i64) -> i64 {
  return value * 2
}
var after = calculate(10)
print before
print after
)"),
            0)
      << errors.str();

  EXPECT_EQ(output.str(), "11\n20\n");
  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Match match = root.matchExact(Byte(const_cast<char *>("calculate")), 0, 9 * Byte::length);
  ASSERT_FALSE(match.isNull());
  EXPECT_FALSE(match.getPhrase().older().isNull());
}

TEST_F(ExpressionLanguageTesting, ResolvesFunctionOverloadsFromTheFunctionPhraseDictionary) {
  ASSERT_EQ(execute(R"(
fn select(value:i64) -> i64 { return 1 }
fn select(value:u8*) -> i64 { return 2 }
fn select_integer() -> i64 { return select(7) }
fn select_string() -> i64 { return select("text") }
var integer_result = select(7)
var string_result = select("text")
var compiled_integer_result = select_integer()
var compiled_string_result = select_string()
)"),
            0)
      << errors.str();
  EXPECT_EQ(context.values().get("integer_result").asInteger(), 1);
  EXPECT_EQ(context.values().get("string_result").asInteger(), 2);
  EXPECT_EQ(context.values().get("compiled_integer_result").asInteger(), 1);
  EXPECT_EQ(context.values().get("compiled_string_result").asInteger(), 2);
  EXPECT_EQ(context.language().findFunctions("select").size(), 2u);

  lexicon::Phrase root = context.lexicon.phrase();
  lexicon::Phrase function = root.matchExact(Byte(const_cast<char *>("select")), 0, 6 * Byte::length).getPhrase();
  ASSERT_TRUE(function.containsSubdictionary());
  EXPECT_FALSE(function.matchExact(Byte(const_cast<char *>("(i64)")), 0, 5 * Byte::length).isNull());
  EXPECT_FALSE(function.matchExact(Byte(const_cast<char *>("(u8*)")), 0, 5 * Byte::length).isNull());
}

TEST_F(ExpressionLanguageTesting, ValidatesFunctionSignaturesAndCalls) {
  EXPECT_NE(execute("let add = fn (left:i64, right:i64) -> i64 { return left + right }\nprint add(1)\n"), 0);
  EXPECT_NE(errors.str().find("expects 2 argument"), std::string::npos);
}
