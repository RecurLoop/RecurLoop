#pragma once

#include <recurloop/Expressions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxCursor.hpp>
#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <utilities/Exception.hpp>

#include <cctype>
#include <cstdint>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace recurloop {
  namespace internal {

    using TokenKind = SyntaxTokenKind;
    using Token = SyntaxToken;
    using Lexer = SyntaxCursor;

    constexpr std::string_view ExpressionDictionaryName{"\0expressions", 12};

    [[noreturn]] void expressionFail(const context::Context &context, std::size_t offset, const std::string &message);

    lexicon::Phrase findPhrase(lexicon::Phrase dictionary, std::string_view key);

    std::int64_t checkedAdd(const context::Context &context, std::int64_t left, std::int64_t right, std::size_t offset);
    std::int64_t checkedSubtract(const context::Context &context, std::int64_t left, std::int64_t right,
                                 std::size_t offset);
    std::int64_t checkedMultiply(const context::Context &context, std::int64_t left, std::int64_t right,
                                 std::size_t offset);

    struct EvaluationFrame {
      const Token *token = nullptr;
      const context::Value *left = nullptr;
      const context::Value *right = nullptr;
      context::Value result;
    };

    extern thread_local EvaluationFrame *currentEvaluation;

    EvaluationFrame &evaluation();

    struct BuiltinFrame {
      const Token *token = nullptr;
      const std::vector<context::Value> *arguments = nullptr;
      context::Value result;
    };

    extern thread_local BuiltinFrame *currentBuiltin;

    BuiltinFrame &builtinFrame();

    const std::vector<context::Value> &builtinArguments(context::Context &context, std::size_t expected);

    context::Value invokeOperator(context::Context &context, lexicon::Phrase &phrase, const Token &token,
                                  const context::Value &left, const context::Value &right = {});

    context::Value invokeBuiltin(context::Context &context, lexicon::Phrase &phrase, const Token &token,
                                 const std::vector<context::Value> &arguments = {});

    void prefixPositive(context::Context &context, lexicon::Phrase &);
    void prefixNegative(context::Context &context, lexicon::Phrase &);
    void prefixLogicalNot(context::Context &, lexicon::Phrase &);
    void infixLogicalOr(context::Context &, lexicon::Phrase &);
    void infixLogicalAnd(context::Context &, lexicon::Phrase &);
    void infixEqual(context::Context &, lexicon::Phrase &);
    void infixNotEqual(context::Context &, lexicon::Phrase &);
    void infixLess(context::Context &context, lexicon::Phrase &);
    void infixLessEqual(context::Context &context, lexicon::Phrase &);
    void infixGreater(context::Context &context, lexicon::Phrase &);
    void infixGreaterEqual(context::Context &context, lexicon::Phrase &);
    void infixAdd(context::Context &context, lexicon::Phrase &);
    void infixSubtract(context::Context &context, lexicon::Phrase &);
    void infixMultiply(context::Context &context, lexicon::Phrase &);
    void infixDivide(context::Context &context, lexicon::Phrase &);
    void infixModulo(context::Context &context, lexicon::Phrase &);

    void builtinStr(context::Context &context, lexicon::Phrase &);
    void builtinType(context::Context &context, lexicon::Phrase &);
    void builtinLen(context::Context &context, lexicon::Phrase &);
    void builtinUpper(context::Context &context, lexicon::Phrase &);
    void builtinLower(context::Context &context, lexicon::Phrase &);
    void builtinTrim(context::Context &context, lexicon::Phrase &);
    void builtinContains(context::Context &context, lexicon::Phrase &);
    void builtinStartsWith(context::Context &context, lexicon::Phrase &);
    void builtinEndsWith(context::Context &context, lexicon::Phrase &);
    void builtinSubstr(context::Context &context, lexicon::Phrase &);
    void builtinReplace(context::Context &context, lexicon::Phrase &);
    void builtinValue(context::Context &context, lexicon::Phrase &);

    void literalTrue(context::Context &, lexicon::Phrase &);
    void literalFalse(context::Context &, lexicon::Phrase &);
    void literalNull(context::Context &, lexicon::Phrase &);

    char peek(context::Context &context);
    std::string readLine(context::Context &context);
    std::string trim(std::string source);

    struct Assignment {
      std::string name;
      lexicon::Phrase operation;
      std::string expression;
      SourceLocation expressionOrigin;
    };

    Assignment assignment(context::Context &context, bool declaration);
    void assignBound(context::Context &context, lexicon::Phrase &invoked);
    context::Value compound(context::Context &context, const Assignment &statement);

    lexicon::Phrase grammarDictionary(lexicon::Phrase &parent, std::string_view name);
    void defineOperator(lexicon::Phrase &dictionary, std::string_view key, lexicon::Phrase::Action action,
                        std::uint8_t precedence, std::uint8_t flags = ExpressionOperator::None,
                        lexicon::Phrase prototype = {});
    void defineCallable(lexicon::Phrase &dictionary, std::string_view key, lexicon::Phrase::Action action,
                        lexicon::Phrase prototype = {});
    void setupExpressionGrammar(lexicon::Phrase &root);

  } // namespace internal
} // namespace recurloop
