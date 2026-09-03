#include "ExpressionsInternal.hpp"

#include <recurloop/PhraseNames.hpp>
#include <recurloop/PhraseDefinition.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/Blocks.hpp>

#include <compiler/LanguageState.hpp>
#include <context/Values.hpp>

#include <algorithm>
#include <cctype>

namespace recurloop {
  namespace internal {

    char peek(context::Context &context) {
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      return context.source.buffer.bits == 0 ? '\0'
                                             : context.source.buffer.str[context.source.buffer.offset / Byte::length];
    }

    std::string readLine(context::Context &context) {
      std::string result;
      while (peek(context) != '\0' && peek(context) != '\n') {
        result.push_back(peek(context));
        context::Source::progress(context, Byte::length);
      }
      return result;
    }

    std::string trim(std::string source) {
      const auto begin =
          std::find_if_not(source.begin(), source.end(), [](unsigned char c) { return std::isspace(c); });
      const auto end =
          std::find_if_not(source.rbegin(), source.rend(), [](unsigned char c) { return std::isspace(c); }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    Assignment assignment(context::Context &context, bool declaration) {
      ParsedPhraseName parsed = PhraseNames::parseAssignment(context);
      std::uint8_t declarationAllowed = 0;
      parsed.operation.fetch(0, declarationAllowed);
      if (declaration && declarationAllowed == 0) expressionFail(context, 0, "a declaration requires '='");
      SourceLocation expressionOrigin;
      const std::string expression = Blocks::captureExpression(context, &expressionOrigin);
      if (expression.empty()) expressionFail(context, 0, "assignment requires an expression");
      return {parsed.qualified(), parsed.operation, expression, std::move(expressionOrigin)};
    }

    void assignBound(context::Context &context, lexicon::Phrase &invoked) {
      ParsedPhraseName parsed = PhraseNames::parseAssignment(context, true);
      if (!parsed.name.empty() || !parsed.path.empty())
        expressionFail(context, 0, "an assignment operator must follow variable '" + invoked.getKey() + "'");
      SourceLocation expressionOrigin;
      const std::string expression = Blocks::captureExpression(context, &expressionOrigin);
      if (expression.empty()) expressionFail(context, 0, "assignment requires an expression");
      context.values().assign(invoked.getKey(), compound(context, {invoked.getKey(), parsed.operation, expression,
                                                                   std::move(expressionOrigin)}));
    }

    context::Value compound(context::Context &context, const Assignment &statement) {
      lexicon::Phrase operation = LanguageGrammar::metadata(statement.operation, sizeof(ExpressionOperator));
      if (operation.isNull()) return Expressions::evaluate(context, statement.expression, statement.expressionOrigin);
      const context::Value left = context.values().get(statement.name);
      const context::Value right = Expressions::evaluate(context, statement.expression, statement.expressionOrigin);
      const Token token{TokenKind::Symbol, operation.getKey(), 0};
      return invokeOperator(context, operation, token, left, right);
    }

    lexicon::Phrase grammarDictionary(lexicon::Phrase &parent, std::string_view name) {
      lexicon::Phrase phrase = parent.append(std::string(name))
                                   .make()
                                   .enableSubdictionary()
                                   .setType(lexicon::phrase::type::getData(parent))
                                   .save();
      return phrase;
    }

    bool isAssignmentAlias(context::Context &context, std::string_view name) {
      lexicon::Phrase root = context.lexicon.phrase();
      lexicon::Phrase grammar = findPhrase(root, ExpressionDictionaryName);
      lexicon::Phrase assignments = findPhrase(grammar, "assignments");
      return !LanguageGrammar::resolve(context, assignments, name).isNull();
    }

    void defineOperator(lexicon::Phrase &dictionary, std::string_view key, lexicon::Phrase::Action action,
                        std::uint8_t precedence, std::uint8_t flags, lexicon::Phrase prototype) {
      lexicon::Draft draft = dictionary.append(std::string(key))
                                 .make(action)
                                 .enableSubdictionary()
                                 .setType(lexicon::phrase::type::getCallable(dictionary));
      if (!prototype.isNull()) draft.setPrototype(prototype);
      lexicon::Phrase phrase = draft.save();
      phrase.store(ExpressionOperator{flags, precedence}).save();
    }

    void defineCallable(lexicon::Phrase &dictionary, std::string_view key, lexicon::Phrase::Action action,
                        lexicon::Phrase prototype) {
      lexicon::Draft draft =
          dictionary.append(std::string(key)).make(action).setType(lexicon::phrase::type::getCallable(dictionary));
      if (!prototype.isNull()) draft.setPrototype(prototype);
      draft.save();
    }

    void setupExpressionGrammar(lexicon::Phrase &root) {
      lexicon::Phrase grammar = grammarDictionary(root, ExpressionDictionaryName);
      lexicon::Phrase prefix = grammarDictionary(grammar, "prefix");
      lexicon::Phrase infix = grammarDictionary(grammar, "infix");
      lexicon::Phrase symbols = grammarDictionary(grammar, "symbols");
      lexicon::Phrase builtins = grammarDictionary(grammar, "builtins");
      lexicon::Phrase literals = grammarDictionary(grammar, "literals");
      lexicon::Phrase assignments = grammarDictionary(grammar, "assignments");
      const auto marker = [&](std::string_view key) { return LanguageGrammar::ensureMarker(root, key); };

      // Install longer assignment markers before their shorter operator
      // prefixes. The radix lexicon can then represent `+` and `+=` as two
      // independent root phrases while both remain aliasable.
      for (std::string_view key : {"=", "+=", "-=", "*=", "/=", "%="})
        LanguageGrammar::ensureMarker(root, key, key == "=" ? lexicon::Phrase{} : root);

      for (std::string_view symbol : {"(", ")", ",", "."})
        symbols.append(std::string(symbol))
            .make()
            .setPrototype(LanguageGrammar::ensureMarker(root, symbol))
            .setType(lexicon::phrase::type::getData(symbols))
            .save();

      defineOperator(prefix, "+", prefixPositive, 7, ExpressionOperator::None, marker("+"));
      defineOperator(prefix, "-", prefixNegative, 7, ExpressionOperator::None, marker("-"));
      defineOperator(prefix, "!", prefixLogicalNot, 7, ExpressionOperator::None, marker("!"));

      defineOperator(infix, "||", infixLogicalOr, 1, ExpressionOperator::SkipRightWhenTrue, marker("||"));
      defineOperator(infix, "&&", infixLogicalAnd, 2, ExpressionOperator::SkipRightWhenFalse, marker("&&"));
      defineOperator(infix, "==", infixEqual, 3, ExpressionOperator::None, marker("=="));
      defineOperator(infix, "!=", infixNotEqual, 3, ExpressionOperator::None, marker("!="));
      defineOperator(infix, "<", infixLess, 4, ExpressionOperator::None, marker("<"));
      defineOperator(infix, "<=", infixLessEqual, 4, ExpressionOperator::None, marker("<="));
      defineOperator(infix, ">", infixGreater, 4, ExpressionOperator::None, marker(">"));
      defineOperator(infix, ">=", infixGreaterEqual, 4, ExpressionOperator::None, marker(">="));
      defineOperator(infix, "+", infixAdd, 5, ExpressionOperator::None, marker("+"));
      defineOperator(infix, "-", infixSubtract, 5, ExpressionOperator::None, marker("-"));
      defineOperator(infix, "*", infixMultiply, 6, ExpressionOperator::None, marker("*"));
      defineOperator(infix, "/", infixDivide, 6, ExpressionOperator::None, marker("/"));
      defineOperator(infix, "%", infixModulo, 6, ExpressionOperator::None, marker("%"));

      for (std::string_view key : {"+=", "-=", "*=", "/=", "%="}) {
        const std::string operatorKey(1, key.front());
        LanguageGrammar::find(root, key).setPrototype(LanguageGrammar::find(infix, operatorKey)).save();
      }

      defineCallable(builtins, "str", builtinStr, marker("str"));
      defineCallable(builtins, "type", builtinType, marker("type"));
      defineCallable(builtins, "len", builtinLen, marker("len"));
      defineCallable(builtins, "upper", builtinUpper, marker("upper"));
      defineCallable(builtins, "lower", builtinLower, marker("lower"));
      defineCallable(builtins, "trim", builtinTrim, marker("trim"));
      defineCallable(builtins, "contains", builtinContains, marker("contains"));
      defineCallable(builtins, "starts_with", builtinStartsWith, marker("starts_with"));
      defineCallable(builtins, "ends_with", builtinEndsWith, marker("ends_with"));
      defineCallable(builtins, "substr", builtinSubstr, marker("substr"));
      defineCallable(builtins, "replace", builtinReplace, marker("replace"));
      defineCallable(builtins, "value", builtinValue, marker("value"));

      defineCallable(literals, "true", literalTrue, marker("true"));
      defineCallable(literals, "false", literalFalse, marker("false"));
      defineCallable(literals, "null", literalNull, marker("null"));

      const auto defineAssignment = [&](std::string_view key, lexicon::Phrase prototype, bool declaration) {
        lexicon::Phrase markerPhrase = LanguageGrammar::ensureMarker(root, key, prototype);
        lexicon::Draft draft = assignments.append(std::string(key))
                                   .make()
                                   .enableSubdictionary()
                                   .setType(lexicon::phrase::type::getData(assignments));
        if (!markerPhrase.isNull()) draft.setPrototype(markerPhrase);
        draft.save().store(static_cast<std::uint8_t>(declaration)).save();
      };
      defineAssignment("=", {}, true);
      for (std::string_view key : {"+", "-", "*", "/", "%"})
        defineAssignment(std::string(key) + "=", findPhrase(infix, key), false);
    }

  } // namespace internal

  lexicon::Phrase Expressions::prefixOperator(context::Context &context, std::string_view name) {
    lexicon::Phrase grammar = internal::findPhrase(context.lexicon.phrase(), internal::ExpressionDictionaryName);
    lexicon::Phrase operators = internal::findPhrase(grammar, "prefix");
    return operators.isNull() || internal::isAssignmentAlias(context, name)
               ? lexicon::Phrase{}
               : LanguageGrammar::resolve(context, operators, name);
  }

  lexicon::Phrase Expressions::infixOperator(context::Context &context, std::string_view name) {
    lexicon::Phrase grammar = internal::findPhrase(context.lexicon.phrase(), internal::ExpressionDictionaryName);
    lexicon::Phrase operators = internal::findPhrase(grammar, "infix");
    return operators.isNull() || internal::isAssignmentAlias(context, name)
               ? lexicon::Phrase{}
               : LanguageGrammar::resolve(context, operators, name);
  }

  ExpressionOperator Expressions::operatorDefinition(lexicon::Phrase &phrase) {
    lexicon::Phrase definition = LanguageGrammar::metadata(phrase, sizeof(ExpressionOperator));
    if (definition.isNull()) THROW(, "expression operator has invalid phrase metadata")
    ExpressionOperator result;
    definition.fetch(0, result);
    return result;
  }

  bool Expressions::isBuiltin(context::Context &context, std::string_view name) {
    lexicon::Phrase grammar = internal::findPhrase(context.lexicon.phrase(), internal::ExpressionDictionaryName);
    return !LanguageGrammar::resolve(context, internal::findPhrase(grammar, "builtins"), name).isNull();
  }

  void Expressions::variable(context::Context &context, lexicon::Phrase &) {
    const internal::Assignment statement = internal::assignment(context, true);
    context.values().define(statement.name, evaluate(context, statement.expression, statement.expressionOrigin), true);
    bindAssignment(context, statement.name);
  }

  void Expressions::constant(context::Context &context, lexicon::Phrase &) {
    const internal::Assignment statement = internal::assignment(context, true);
    context.values().define(statement.name, evaluate(context, statement.expression, statement.expressionOrigin), false);
    bindAssignment(context, statement.name);
  }

  void Expressions::bindAssignment(context::Context &context, std::string_view name) {
    if (name.empty()) return;
    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Match existing = root.matchExact(
        Byte(const_cast<char *>(name.data())), 0, name.size() * Byte::length,
        [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); });
    // Data-only grammar markers (for example the canonical `value` builtin)
    // are not executable bindings and must not reserve ordinary variable
    // names. A real phrase still wins and keeps the existing binding stable.
    if (!existing.isNull()) {
      lexicon::Phrase existingPhrase = existing.getPhrase();
      if (existingPhrase.isElaboratable() || existingPhrase.containsAction()) return;
    }
    lexicon::Phrase phrase = root.append(std::string(name))
                                 .make(internal::assignBound)
                                 .setType(lexicon::phrase::type::getElaborate(root))
                                 .save();
    compiler::LanguageState::bind(phrase);
  }

  void Expressions::assign(context::Context &context, lexicon::Phrase &) {
    if (PhraseDefinition::mutate(context)) return;
    const internal::Assignment statement = internal::assignment(context, false);
    context.values().assign(statement.name, internal::compound(context, statement));
  }

  void Expressions::print(context::Context &context, lexicon::Phrase &) {
    SourceLocation origin;
    const std::string source = Blocks::captureExpression(context, &origin);
    if (source.empty()) internal::expressionFail(context, 0, "print requires an expression");
    *context.io.out << evaluate(context, source, origin).format() << '\n';
    context.io.out->flush();
  }

  void Expressions::assertTrue(context::Context &context, lexicon::Phrase &) {
    SourceLocation origin;
    const std::string source = Blocks::captureExpression(context, &origin);
    if (source.empty()) internal::expressionFail(context, 0, "assert requires an expression");
    if (!evaluate(context, source, origin).asBoolean()) {
      const SourceLocation location = sourceLocationAt(origin, source, 0);
      THROW_AT(location, "assertion failed: " << source)
    }
  }

  void Expressions::setup(context::Context &context) {
    context.actions().define("expressions.operator.prefix-positive", internal::prefixPositive);
    context.actions().define("expressions.operator.prefix-negative", internal::prefixNegative);
    context.actions().define("expressions.operator.prefix-not", internal::prefixLogicalNot);
    context.actions().define("expressions.operator.infix-or", internal::infixLogicalOr);
    context.actions().define("expressions.operator.infix-and", internal::infixLogicalAnd);
    context.actions().define("expressions.operator.infix-equal", internal::infixEqual);
    context.actions().define("expressions.operator.infix-not-equal", internal::infixNotEqual);
    context.actions().define("expressions.operator.infix-less", internal::infixLess);
    context.actions().define("expressions.operator.infix-less-equal", internal::infixLessEqual);
    context.actions().define("expressions.operator.infix-greater", internal::infixGreater);
    context.actions().define("expressions.operator.infix-greater-equal", internal::infixGreaterEqual);
    context.actions().define("expressions.operator.infix-add", internal::infixAdd);
    context.actions().define("expressions.operator.infix-subtract", internal::infixSubtract);
    context.actions().define("expressions.operator.infix-multiply", internal::infixMultiply);
    context.actions().define("expressions.operator.infix-divide", internal::infixDivide);
    context.actions().define("expressions.operator.infix-modulo", internal::infixModulo);
    context.actions().define("expressions.builtin.str", internal::builtinStr);
    context.actions().define("expressions.builtin.type", internal::builtinType);
    context.actions().define("expressions.builtin.len", internal::builtinLen);
    context.actions().define("expressions.builtin.upper", internal::builtinUpper);
    context.actions().define("expressions.builtin.lower", internal::builtinLower);
    context.actions().define("expressions.builtin.trim", internal::builtinTrim);
    context.actions().define("expressions.builtin.contains", internal::builtinContains);
    context.actions().define("expressions.builtin.starts-with", internal::builtinStartsWith);
    context.actions().define("expressions.builtin.ends-with", internal::builtinEndsWith);
    context.actions().define("expressions.builtin.substr", internal::builtinSubstr);
    context.actions().define("expressions.builtin.replace", internal::builtinReplace);
    context.actions().define("expressions.builtin.value", internal::builtinValue);
    context.actions().define("expressions.literal.true", internal::literalTrue);
    context.actions().define("expressions.literal.false", internal::literalFalse);
    context.actions().define("expressions.literal.null", internal::literalNull);
    context.actions().define("expressions.variable", variable);
    context.actions().define("expressions.constant", constant);
    context.actions().define("expressions.assign", assign);
    context.actions().define("expressions.assign-bound", internal::assignBound);
    context.actions().define("expressions.print", print);
    context.actions().define("expressions.assert", assertTrue);
    lexicon::Phrase root = context.lexicon.phrase();
    internal::setupExpressionGrammar(root);
    PhraseNames::setup(context);
    context::Values::setup(root);
    const auto bind = [&](std::string key, lexicon::Phrase::Action action) {
      lexicon::Phrase phrase =
          root.append(std::move(key)).make(action).setType(lexicon::phrase::type::getElaborate(root)).save();
      compiler::LanguageState::bind(phrase);
    };
    bind("var", variable);
    bind("const", constant);
    bind("set", assign);
    bind("print", print);
    bind("assert", assertTrue);
  }

} // namespace recurloop
