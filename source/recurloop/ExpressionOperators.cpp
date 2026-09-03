#include "ExpressionsInternal.hpp"

#include <algorithm>
#include <cctype>
#include <limits>

namespace recurloop {
namespace internal {

  int compare(context::Context &context, const EvaluationFrame &frame) {
    const context::Value &left = *frame.left;
    const context::Value &right = *frame.right;
    if (left.isInteger() && right.isInteger())
      return left.asInteger() < right.asInteger() ? -1 : left.asInteger() > right.asInteger() ? 1 : 0;
    if (left.isNumber() && right.isNumber())
      return left.asReal() < right.asReal() ? -1 : left.asReal() > right.asReal() ? 1 : 0;
    if (left.isString() && right.isString()) return left.asString().compare(right.asString());
    expressionFail(context, frame.token->offset, "comparison requires two numbers or two strings");
  }

  void requireNumbers(context::Context &context, const EvaluationFrame &frame) {
    if (!frame.left->isNumber() || !frame.right->isNumber())
      expressionFail(context, frame.token->offset, "'" + frame.token->text + "' requires numeric operands");
  }

  void prefixPositive(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    if (!frame.left->isNumber())
      expressionFail(context, frame.token->offset, "unary '" + frame.token->text + "' requires a number");
    frame.result = *frame.left;
  }

  void prefixNegative(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    if (!frame.left->isNumber())
      expressionFail(context, frame.token->offset, "unary '" + frame.token->text + "' requires a number");
    if (frame.left->isInteger()) {
      if (frame.left->asInteger() == std::numeric_limits<std::int64_t>::min())
        expressionFail(context, frame.token->offset, "integer negation overflows");
      frame.result = context::Value(-frame.left->asInteger());
    } else {
      frame.result = context::Value(-frame.left->asReal());
    }
  }

  void prefixLogicalNot(context::Context &, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(!frame.left->asBoolean());
  }

  void infixLogicalOr(context::Context &, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(frame.left->asBoolean() || frame.right->asBoolean());
  }

  void infixLogicalAnd(context::Context &, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(frame.left->asBoolean() && frame.right->asBoolean());
  }

  void infixEqual(context::Context &, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(*frame.left == *frame.right);
  }

  void infixNotEqual(context::Context &, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(!(*frame.left == *frame.right));
  }

  void infixLess(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(compare(context, frame) < 0);
  }

  void infixLessEqual(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(compare(context, frame) <= 0);
  }

  void infixGreater(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(compare(context, frame) > 0);
  }

  void infixGreaterEqual(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    frame.result = context::Value(compare(context, frame) >= 0);
  }

  void infixAdd(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    if (frame.left->isString() || frame.right->isString()) {
      frame.result = context::Value(frame.left->format() + frame.right->format());
      return;
    }
    requireNumbers(context, frame);
    frame.result = frame.left->isInteger() && frame.right->isInteger()
                       ? context::Value(checkedAdd(context, frame.left->asInteger(), frame.right->asInteger(),
                                                   frame.token->offset))
                       : context::Value(frame.left->asReal() + frame.right->asReal());
  }

  void infixSubtract(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    requireNumbers(context, frame);
    frame.result = frame.left->isInteger() && frame.right->isInteger()
                       ? context::Value(checkedSubtract(context, frame.left->asInteger(), frame.right->asInteger(),
                                                        frame.token->offset))
                       : context::Value(frame.left->asReal() - frame.right->asReal());
  }

  void infixMultiply(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    requireNumbers(context, frame);
    frame.result = frame.left->isInteger() && frame.right->isInteger()
                       ? context::Value(checkedMultiply(context, frame.left->asInteger(), frame.right->asInteger(),
                                                        frame.token->offset))
                       : context::Value(frame.left->asReal() * frame.right->asReal());
  }

  void infixDivide(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    requireNumbers(context, frame);
    if (frame.right->asReal() == 0) expressionFail(context, frame.token->offset, "division by zero");
    if (frame.left->isInteger() && frame.right->isInteger()) {
      if (frame.left->asInteger() == std::numeric_limits<std::int64_t>::min() && frame.right->asInteger() == -1)
        expressionFail(context, frame.token->offset, "integer division overflows");
      frame.result = context::Value(frame.left->asInteger() / frame.right->asInteger());
    } else {
      frame.result = context::Value(frame.left->asReal() / frame.right->asReal());
    }
  }

  void infixModulo(context::Context &context, lexicon::Phrase &) {
    EvaluationFrame &frame = evaluation();
    if (!frame.left->isInteger() || !frame.right->isInteger())
      expressionFail(context, frame.token->offset, "'%' requires integer operands");
    if (frame.right->asInteger() == 0) expressionFail(context, frame.token->offset, "integer modulo by zero");
    frame.result =
        frame.left->asInteger() == std::numeric_limits<std::int64_t>::min() && frame.right->asInteger() == -1
            ? context::Value(std::int64_t{0})
            : context::Value(frame.left->asInteger() % frame.right->asInteger());
  }

  void builtinStr(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    builtinFrame().result = context::Value(values[0].format());
  }
  void builtinType(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    builtinFrame().result = context::Value(values[0].typeName());
  }
  void builtinLen(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    builtinFrame().result = context::Value(static_cast<std::int64_t>(values[0].asString().size()));
  }
  void builtinUpper(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    std::string result = values[0].asString();
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char character) { return static_cast<char>(std::toupper(character)); });
    builtinFrame().result = context::Value(std::move(result));
  }
  void builtinLower(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    std::string result = values[0].asString();
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
    builtinFrame().result = context::Value(std::move(result));
  }
  void builtinTrim(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    const std::string &source = values[0].asString();
    const auto begin =
        std::find_if_not(source.begin(), source.end(), [](unsigned char c) { return std::isspace(c); });
    const auto end =
        std::find_if_not(source.rbegin(), source.rend(), [](unsigned char c) { return std::isspace(c); }).base();
    builtinFrame().result = context::Value(begin < end ? std::string(begin, end) : std::string{});
  }
  void builtinContains(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 2);
    builtinFrame().result = context::Value(values[0].asString().find(values[1].asString()) != std::string::npos);
  }
  void builtinStartsWith(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 2);
    builtinFrame().result = context::Value(values[0].asString().starts_with(values[1].asString()));
  }
  void builtinEndsWith(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 2);
    builtinFrame().result = context::Value(values[0].asString().ends_with(values[1].asString()));
  }
  void builtinSubstr(context::Context &context, lexicon::Phrase &) {
    BuiltinFrame &frame = builtinFrame();
    const auto &values = *frame.arguments;
    if (values.size() != 2 && values.size() != 3)
      expressionFail(context, frame.token->offset, "'substr' expects 2 or 3 arguments");
    const std::string &source = values[0].asString();
    const std::int64_t begin = values[1].asInteger();
    if (begin < 0 || static_cast<std::size_t>(begin) > source.size())
      expressionFail(context, frame.token->offset, "substring start is out of range");
    const std::size_t size = values.size() == 3 ? static_cast<std::size_t>(values[2].asInteger()) : std::string::npos;
    if (values.size() == 3 && values[2].asInteger() < 0)
      expressionFail(context, frame.token->offset, "substring length cannot be negative");
    frame.result = context::Value(source.substr(begin, size));
  }
  void builtinReplace(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 3);
    std::string result = values[0].asString();
    const std::string &from = values[1].asString();
    const std::string &to = values[2].asString();
    if (from.empty()) expressionFail(context, builtinFrame().token->offset, "replace source cannot be empty");
    std::size_t cursor = 0;
    while ((cursor = result.find(from, cursor)) != std::string::npos) {
      result.replace(cursor, from.size(), to);
      cursor += to.size();
    }
    builtinFrame().result = context::Value(std::move(result));
  }
  void builtinValue(context::Context &context, lexicon::Phrase &) {
    const auto &values = builtinArguments(context, 1);
    builtinFrame().result = context.values().get(values[0].asString());
  }
  void literalTrue(context::Context &, lexicon::Phrase &) {
    builtinFrame().result = context::Value(true);
  }
  void literalFalse(context::Context &, lexicon::Phrase &) {
    builtinFrame().result = context::Value(false);
  }
  void literalNull(context::Context &, lexicon::Phrase &) {
    builtinFrame().result = context::Value();
  }

} // namespace internal
} // namespace recurloop
