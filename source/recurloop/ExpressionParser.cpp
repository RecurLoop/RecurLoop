#include "ExpressionsInternal.hpp"

#include <recurloop/Assembler.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/PhraseNames.hpp>

#include <compiler/DynamicLinker.hpp>
#include <compiler/JitLinker.hpp>

#include <algorithm>
#include <charconv>
#include <cmath>

#if defined(__x86_64__)
extern "C" std::uintptr_t recurloop_call_scalar_native_sysv(std::uintptr_t entry, const std::uintptr_t *args);
asm(R"(
  .text
  .global recurloop_call_scalar_native_sysv
  .type recurloop_call_scalar_native_sysv, @function
recurloop_call_scalar_native_sysv:
  mov %rdi, %rax
  mov %rsi, %r10
  mov 0(%r10), %rdi
  mov 8(%r10), %rsi
  mov 16(%r10), %rdx
  mov 24(%r10), %rcx
  mov 32(%r10), %r8
  mov 40(%r10), %r9
  sub $8, %rsp
  call *%rax
  add $8, %rsp
  ret
  .size recurloop_call_scalar_native_sysv, .-recurloop_call_scalar_native_sysv
)");
#endif

namespace recurloop {
  namespace internal {

    struct ExpressionDiagnostic {
      std::string_view source;
      SourceLocation origin;
    };

    thread_local ExpressionDiagnostic *currentExpressionDiagnostic = nullptr;

    lexicon::Phrase findPhrase(lexicon::Phrase dictionary, std::string_view key) {
      return LanguageGrammar::find(dictionary, key);
    }

    [[noreturn]] void expressionFail(const context::Context &context, std::size_t offset, const std::string &message) {
      const SourceLocation origin = currentExpressionDiagnostic == nullptr
                                        ? SourceLocation{context.source.path, context.source.line, context.source.position}
                                        : currentExpressionDiagnostic->origin;
      const std::string_view source =
          currentExpressionDiagnostic == nullptr ? std::string_view{} : currentExpressionDiagnostic->source;
      const SourceLocation location = sourceLocationAt(origin, source, offset);
      THROW_AT(location, "expression: " << message)
    }

    std::int64_t
        checkedAdd(const context::Context &context, std::int64_t left, std::int64_t right, std::size_t offset) {
      std::int64_t result;
      if (__builtin_add_overflow(left, right, &result)) expressionFail(context, offset, "integer addition overflows");
      return result;
    }
    std::int64_t checkedSubtract(const context::Context &context, std::int64_t left, std::int64_t right,
                                 std::size_t offset) {
      std::int64_t result;
      if (__builtin_sub_overflow(left, right, &result))
        expressionFail(context, offset, "integer subtraction overflows");
      return result;
    }
    std::int64_t checkedMultiply(const context::Context &context, std::int64_t left, std::int64_t right,
                                 std::size_t offset) {
      std::int64_t result;
      if (__builtin_mul_overflow(left, right, &result))
        expressionFail(context, offset, "integer multiplication overflows");
      return result;
    }

    thread_local EvaluationFrame *currentEvaluation = nullptr;

    EvaluationFrame &evaluation() {
      if (currentEvaluation == nullptr) THROW(, "expression primitive invoked without an evaluation frame")
      return *currentEvaluation;
    }

    thread_local BuiltinFrame *currentBuiltin = nullptr;

    BuiltinFrame &builtinFrame() {
      if (currentBuiltin == nullptr) THROW(, "expression builtin invoked without a call frame")
      return *currentBuiltin;
    }

    const std::vector<context::Value> &builtinArguments(context::Context &context, std::size_t expected) {
      BuiltinFrame &frame = builtinFrame();
      if (frame.arguments->size() != expected)
        expressionFail(context, frame.token->offset,
                       "'" + frame.token->text + "' expects " + std::to_string(expected) + " argument(s), got " +
                           std::to_string(frame.arguments->size()));
      return *frame.arguments;
    }

    class Parser;

    struct ParsedExpression {
      Token token;
      context::Value value;
      bool named = false;
      bool resolved = false;
    };

    struct PrimaryParseFrame {
      Parser *parser = nullptr;
      Token start;
      bool active = false;
      ParsedExpression result;
      bool produced = false;
    };

    struct PostfixParseFrame {
      Parser *parser = nullptr;
      Token operation;
      bool active = false;
      ParsedExpression result;
      bool produced = false;
    };

    thread_local PrimaryParseFrame *currentPrimaryParse = nullptr;
    thread_local PostfixParseFrame *currentPostfixParse = nullptr;

    PrimaryParseFrame &primaryParseFrame() {
      if (currentPrimaryParse == nullptr) THROW(, "expression primary phrase invoked without a parser frame")
      return *currentPrimaryParse;
    }

    PostfixParseFrame &postfixParseFrame() {
      if (currentPostfixParse == nullptr) THROW(, "expression postfix phrase invoked without a parser frame")
      return *currentPostfixParse;
    }

    context::Value invokeOperator(context::Context &context, lexicon::Phrase &phrase, const Token &token,
                                  const context::Value &left, const context::Value &right) {
      EvaluationFrame frame{&token, &left, &right, {}};
      EvaluationFrame *previous = currentEvaluation;
      currentEvaluation = &frame;
      try {
        phrase.invoke(context);
      } catch (const Exception &error) {
        currentEvaluation = previous;
        if (error.hasSourceLocation()) throw;
        expressionFail(context, token.offset, error.description());
      } catch (const std::exception &error) {
        currentEvaluation = previous;
        expressionFail(context, token.offset, error.what());
      } catch (...) {
        currentEvaluation = previous;
        expressionFail(context, token.offset, "unknown internal error");
      }
      currentEvaluation = previous;
      return frame.result;
    }

    context::Value invokeBuiltin(context::Context &context, lexicon::Phrase &phrase, const Token &token,
                                 const std::vector<context::Value> &arguments) {
      BuiltinFrame frame{&token, &arguments, {}};
      BuiltinFrame *previous = currentBuiltin;
      currentBuiltin = &frame;
      try {
        phrase.invoke(context);
      } catch (const Exception &error) {
        currentBuiltin = previous;
        if (error.hasSourceLocation()) throw;
        expressionFail(context, token.offset, error.description());
      } catch (const std::exception &error) {
        currentBuiltin = previous;
        expressionFail(context, token.offset, error.what());
      } catch (...) {
        currentBuiltin = previous;
        expressionFail(context, token.offset, "unknown internal error");
      }
      currentBuiltin = previous;
      return frame.result;
    }

    class Parser {
    public:
      Parser(context::Context &context, std::string_view source)
          : context(context), grammar(findPhrase(context.lexicon.phrase(), ExpressionDictionaryName)),
            prefixOperators(findPhrase(grammar, "prefix")), infixOperators(findPhrase(grammar, "infix")),
            primaries(findPhrase(grammar, "primary")), postfixes(findPhrase(grammar, "postfix")),
            symbols(findPhrase(grammar, "symbols")), builtins(findPhrase(grammar, "builtins")),
            dynamicBuiltins(findPhrase(grammar, "dynamic")), literals(findPhrase(grammar, "literals")),
            lexer(context, source, {symbols, prefixOperators, infixOperators, primaries, postfixes}, expressionFail,
                  {}) {
        if (grammar.isNull()) THROW(, "expression phrase grammar is not installed")
        if (prefixOperators.isNull() || infixOperators.isNull() || primaries.isNull() || postfixes.isNull() ||
            symbols.isNull())
          THROW(, "expression phrase grammar is incomplete")
      }

      context::Value parse() {
        context::Value result = expression(1, true);
        if (lexer.current().kind != TokenKind::End)
          expressionFail(context, lexer.current().offset, "unexpected token '" + lexer.current().text + "'");
        return result;
      }

    private:
      context::Value expression(std::uint8_t minimumPrecedence, bool active) {
        context::Value left = prefix(active);
        while (lexer.current().kind == TokenKind::Symbol) {
          lexicon::Phrase phrase = LanguageGrammar::resolve(context, infixOperators, lexer.current().text);
          if (phrase.isNull()) break;
          const ExpressionOperator definition = Expressions::operatorDefinition(phrase);
          if (definition.precedence < minimumPrecedence) break;
          const Token token = lexer.take();
          bool rightActive = active;
          if (active && (definition.flags & ExpressionOperator::SkipRightWhenTrue)) rightActive = !left.asBoolean();
          if (active && (definition.flags & ExpressionOperator::SkipRightWhenFalse)) rightActive = left.asBoolean();
          const context::Value right = expression(definition.precedence + 1, rightActive);
          if (active) left = invokeOperator(context, phrase, token, left, right);
        }
        return left;
      }

      context::Value prefix(bool active) {
        if (lexer.current().kind != TokenKind::Symbol) return primary(active);
        lexicon::Phrase phrase = LanguageGrammar::resolve(context, prefixOperators, lexer.current().text);
        if (phrase.isNull()) return primary(active);
        const Token token = lexer.take();
        context::Value value = prefix(active);
        if (!active) return {};
        return invokeOperator(context, phrase, token, value);
      }

      std::vector<context::Value> arguments(bool active) {
        std::vector<context::Value> result;
        if (lexer.accept(")")) return result;
        while (true) {
          result.push_back(expression(1, active));
          if (lexer.accept(")")) return result;
          lexer.expect(",");
        }
      }

      ParsedExpression invokePrimary(lexicon::Phrase syntax, Token start, bool active) {
        PrimaryParseFrame frame{this, std::move(start), active, {}, false};
        PrimaryParseFrame *previous = currentPrimaryParse;
        currentPrimaryParse = &frame;
        try {
          syntax.invoke(context);
        } catch (...) {
          currentPrimaryParse = previous;
          throw;
        }
        currentPrimaryParse = previous;
        if (!frame.produced)
          expressionFail(context, frame.start.offset, "expression primary phrase did not produce a value");
        return std::move(frame.result);
      }

      ParsedExpression invokePostfix(lexicon::Phrase syntax, Token operation, ParsedExpression base, bool active) {
        PostfixParseFrame frame{this, std::move(operation), active, std::move(base), false};
        PostfixParseFrame *previous = currentPostfixParse;
        currentPostfixParse = &frame;
        try {
          syntax.invoke(context);
        } catch (...) {
          currentPostfixParse = previous;
          throw;
        }
        currentPostfixParse = previous;
        if (!frame.produced)
          expressionFail(context, frame.operation.offset, "expression postfix phrase did not produce a value");
        return std::move(frame.result);
      }

      context::Value resolve(ParsedExpression &parsed, bool active) {
        if (parsed.resolved) return parsed.value;
        if (!parsed.named)
          expressionFail(context, parsed.token.offset, "expression phrase produced an unresolved value");
        lexicon::Phrase literal = LanguageGrammar::resolve(context, literals, parsed.token.text);
        if (!literal.isNull()) {
          parsed.value = active ? invokeBuiltin(context, literal, parsed.token) : context::Value();
        } else if (active) {
          try {
            parsed.value = context.values().get(parsed.token.text);
          } catch (const Exception &error) {
            if (error.hasSourceLocation()) throw;
            expressionFail(context, parsed.token.offset, error.description());
          }
        }
        parsed.resolved = true;
        return parsed.value;
      }

      std::vector<compiler::TypeId> nativeArgumentTypes(const std::vector<context::Value> &values) {
        std::vector<compiler::TypeId> argumentTypes;
        argumentTypes.reserve(values.size());
        for (const context::Value &value : values) {
          if (value.isReal())
            argumentTypes.push_back(context.language().types.find("f64"));
          else if (value.isString() || value.isNull())
            argumentTypes.push_back(context.language().types.pointerTo(context.language().types.find("u8")));
          else
            argumentTypes.push_back(context.language().types.find("i64"));
        }
        return argumentTypes;
      }

      context::Value callNativeFunction(const Token &name, const std::vector<context::Value> &values) {
        const std::vector<compiler::TypeId> argumentTypes = nativeArgumentTypes(values);
        const std::optional<compiler::TypedFunction> function =
            context.language().resolveFunction(name.text, argumentTypes);
        if (!function) {
          const std::vector<compiler::TypedFunction> candidates = context.language().findFunctions(name.text);
          if (!candidates.empty())
            expressionFail(context, name.offset,
                           "'" + name.text + "' expects " + std::to_string(candidates.front().parameterTypes.size()) +
                               " argument(s) in its available overloads, got " + std::to_string(values.size()));
          expressionFail(context, name.offset, "unknown function '" + name.text + "'");
        }
        if (function->signature.convention.name != "sysv-amd64")
          expressionFail(context, name.offset, "native runtime calls currently require the sysv-amd64 ABI");
        if ((!function->signature.variadic && values.size() != function->parameterTypes.size()) ||
            (function->signature.variadic && values.size() < function->parameterTypes.size()))
          expressionFail(context, name.offset,
                         "'" + name.text + "' expects " + std::to_string(function->parameterTypes.size()) +
                             " argument(s), got " + std::to_string(values.size()));

        std::uintptr_t entry = 0;
        if (const std::optional<compiler::Module> module = context.language().findModule(function->signature.symbol)) {
          const compiler::Module linked = context.language().composeModule(*module);
          const compiler::JitImage image = compiler::JitLinker::link(
              linked, context.runtime, [&](std::string_view sym) -> std::optional<std::uintptr_t> {
                return compiler::DynamicLinker::instance().resolveFromDefault(sym);
              });
          entry = image.address(function->signature.symbol);
        } else {
          if (function->imported) {
            if (auto addr = compiler::DynamicLinker::instance().resolveFromDefault(function->signature.symbol)) {
              entry = *addr;
            } else {
              expressionFail(context, name.offset, "cannot resolve imported function '" + std::string(name.text) + "'");
            }
          } else {
            lexicon::Phrase phrase = context.lexicon.phrase();
            std::string_view qualified = name.text;
            while (!qualified.empty()) {
              const std::size_t separator = qualified.find(':');
              phrase = findPhrase(phrase, qualified.substr(0, separator));
              if (phrase.isNull() || separator == std::string_view::npos) break;
              qualified.remove_prefix(separator + 1);
            }
            if (phrase.isNull()) expressionFail(context, name.offset, "unknown function '" + name.text + "'");
            const std::string key =
                context.language().functionKey(function->parameterTypes, function->signature.variadic);
            phrase = findPhrase(phrase, key);
            if (phrase.isNull())
              expressionFail(context, name.offset, "function overload phrase is unavailable for '" + name.text + "'");
            entry = recurloop::Assembler::nativeEntry(phrase);
          }
        }
        const auto resultType = context.language().types.get(function->resultType);
        const bool scalarResult =
            resultType.kind == compiler::TypeKind::Void || resultType.kind == compiler::TypeKind::Integer ||
            resultType.kind == compiler::TypeKind::Pointer || resultType.kind == compiler::TypeKind::Function;
        bool scalarParameters = true;
        for (compiler::TypeId parameterId : function->parameterTypes) {
          const auto parameterType = context.language().types.get(parameterId);
          if (parameterType.kind != compiler::TypeKind::Integer && parameterType.kind != compiler::TypeKind::Pointer &&
              parameterType.kind != compiler::TypeKind::Function) {
            scalarParameters = false;
            break;
          }
        }
        if (scalarResult && scalarParameters) {
          std::uintptr_t raw[6] = {};
          for (std::size_t index = 0; index < values.size(); ++index) {
            const auto parameterType = context.language().types.get(function->parameterTypes[index]);
            if (parameterType.kind == compiler::TypeKind::Pointer ||
                parameterType.kind == compiler::TypeKind::Function) {
              if (values[index].isNull()) {
                raw[index] = 0;
              } else if (values[index].isInteger()) {
                raw[index] = static_cast<std::uintptr_t>(values[index].asInteger());
              } else if (values[index].isString()) {
                raw[index] = reinterpret_cast<std::uintptr_t>(values[index].asString().c_str());
              } else {
                expressionFail(context, name.offset,
                               "pointer argument '" + std::to_string(index + 1) + "' for '" + name.text +
                                   "' must be null, integer address, or string storage");
              }
            } else {
              if (values[index].isInteger())
                raw[index] = static_cast<std::uintptr_t>(values[index].asInteger());
              else if (values[index].isBoolean())
                raw[index] = values[index].asBoolean() ? 1u : 0u;
              else
                expressionFail(context, name.offset,
                               "integer argument '" + std::to_string(index + 1) + "' for '" + name.text +
                                   "' must be an integer or bool");
            }
          }

          if (values.size() > 6)
            expressionFail(context, name.offset, "native runtime calls currently support six scalar arguments");
#if defined(__x86_64__)
          const std::uintptr_t result = recurloop_call_scalar_native_sysv(entry, raw);
#else
          expressionFail(context, name.offset, "scalar native runtime calls are only implemented on x86-64");
#endif

          if (resultType.kind == compiler::TypeKind::Void) return context::Value();
          return context::Value(static_cast<std::int64_t>(result));
        }
        if (function->parameterTypes.empty() && function->resultType == context.language().types.find("i64")) {
          return context::Value(reinterpret_cast<std::int64_t (*)()>(entry)());
        }
        if (function->parameterTypes.size() == 1 && function->resultType == context.language().types.find("i64") &&
            values[0].isInteger()) {
          return context::Value(reinterpret_cast<std::int64_t (*)(std::int64_t)>(entry)(values[0].asInteger()));
        }
        if (function->parameterTypes.size() == 1 && function->resultType == context.language().types.find("i64") &&
            values[0].isReal()) {
          return context::Value(reinterpret_cast<std::int64_t (*)(double)>(entry)(values[0].asReal()));
        }
        if (function->parameterTypes.size() == 2 && function->resultType == context.language().types.find("i64") &&
            values[0].isInteger() && values[1].isInteger()) {
          return context::Value(reinterpret_cast<std::int64_t (*)(std::int64_t, std::int64_t)>(entry)(
              values[0].asInteger(), values[1].asInteger()));
        }
        expressionFail(context, name.offset, "native runtime calls currently support only scalar integer ABI calls");
      }

      context::Value builtin(const Token &name, std::vector<context::Value> values) {
        try {
          lexicon::Phrase phrase = LanguageGrammar::resolve(context, builtins, name.text);
          if (!phrase.isNull()) return invokeBuiltin(context, phrase, name, values);

          const std::vector<compiler::TypedFunction> native = context.language().findFunctions(name.text);
          if (!native.empty() && context.language().resolveFunction(name.text, nativeArgumentTypes(values)))
            return callNativeFunction(name, values);

          phrase = LanguageGrammar::resolve(context, dynamicBuiltins, name.text);
          if (!phrase.isNull()) return invokeBuiltin(context, phrase, name, values);
          if (!native.empty()) return callNativeFunction(name, values);
          expressionFail(context, name.offset, "unknown function '" + name.text + "'");
        } catch (const Exception &error) {
          if (error.hasSourceLocation()) throw;
          expressionFail(context, name.offset, error.description());
        } catch (const std::exception &error) {
          expressionFail(context, name.offset, error.what());
        }
      }

    public:
      ParsedExpression parseGrouped(const Token &start, bool active) {
        ParsedExpression result;
        result.token = start;
        result.value = expression(1, active);
        result.resolved = true;
        lexer.expect(")");
        return result;
      }

      ParsedExpression parseQualification(Token operation, ParsedExpression base) {
        if (!base.named || base.resolved)
          expressionFail(context, operation.offset, "name qualification requires an unresolved name");
        const Token component = lexer.take();
        if (component.kind != TokenKind::Identifier)
          expressionFail(context, component.offset, "expected name after '" + operation.text + "'");
        base.token.text += ":" + component.text;
        return base;
      }

      ParsedExpression parseCall(Token operation, ParsedExpression base, bool active) {
        if (!base.named || base.resolved)
          expressionFail(context, operation.offset, "a direct call requires a named function");
        std::vector<context::Value> values = arguments(active);
        base.value = active ? builtin(base.token, std::move(values)) : context::Value();
        base.resolved = true;
        return base;
      }

      ParsedExpression parseMember(Token, ParsedExpression base, bool active) {
        base.value = resolve(base, active);
        const Token method = lexer.take();
        if (method.kind != TokenKind::Identifier)
          expressionFail(context, method.offset, "expected method name after '.'");
        lexicon::Phrase call = LanguageGrammar::resolve(context, postfixes, lexer.current().text);
        lexicon::Phrase canonicalCall = findPhrase(postfixes, "(");
        if (call.isNull() || canonicalCall.isNull() || call.getAddress() != canonicalCall.getAddress())
          expressionFail(context, method.offset, "expected a call after method name");
        lexer.take();
        std::vector<context::Value> values = arguments(active);
        if (active) {
          values.insert(values.begin(), base.value);
          base.value = builtin(method, std::move(values));
        }
        base.named = false;
        base.resolved = true;
        return base;
      }

    private:
      context::Value primary(bool active) {
        Token token = lexer.take();
        ParsedExpression result;
        result.token = token;
        if (token.kind == TokenKind::Integer) {
          std::string text = token.text;
          text.erase(std::remove(text.begin(), text.end(), '_'), text.end());
          int base = 10;
          if (text.starts_with("0x") || text.starts_with("0X")) {
            base = 16;
            text.erase(0, 2);
          } else if (text.starts_with("0b") || text.starts_with("0B")) {
            base = 2;
            text.erase(0, 2);
          } else if (text.starts_with("0o") || text.starts_with("0O")) {
            base = 8;
            text.erase(0, 2);
          }
          std::int64_t value = 0;
          const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value, base);
          if (text.empty() || error != std::errc() || end != text.data() + text.size())
            expressionFail(context, token.offset, "invalid integer literal");
          result.value = context::Value(value);
          result.resolved = true;
        } else if (token.kind == TokenKind::Real) {
          std::string text = token.text;
          text.erase(std::remove(text.begin(), text.end(), '_'), text.end());
          double value = 0;
          const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value);
          if (error != std::errc() || end != text.data() + text.size() || !std::isfinite(value))
            expressionFail(context, token.offset, "invalid real literal");
          result.value = context::Value(value);
          result.resolved = true;
        } else if (token.kind == TokenKind::String) {
          result.value = context::Value(token.text);
          result.resolved = true;
        } else {
          lexicon::Phrase syntax = LanguageGrammar::resolve(context, primaries, token.text);
          if (!syntax.isNull()) {
            result = invokePrimary(syntax, std::move(token), active);
          } else if (token.kind == TokenKind::Identifier) {
            result.named = true;
          } else {
            expressionFail(context, token.offset, "expected a value, variable or primary phrase");
          }
        }

        while (true) {
          lexicon::Phrase syntax = LanguageGrammar::resolve(context, postfixes, lexer.current().text);
          if (syntax.isNull()) break;
          result = invokePostfix(syntax, lexer.take(), std::move(result), active);
        }
        return resolve(result, active);
      }

      context::Context &context;
      lexicon::Phrase grammar;
      lexicon::Phrase prefixOperators;
      lexicon::Phrase infixOperators;
      lexicon::Phrase primaries;
      lexicon::Phrase postfixes;
      lexicon::Phrase symbols;
      lexicon::Phrase builtins;
      lexicon::Phrase dynamicBuiltins;
      lexicon::Phrase literals;
      Lexer lexer;
    };

    void primaryGroup(context::Context &, lexicon::Phrase &) {
      PrimaryParseFrame &frame = primaryParseFrame();
      frame.result = frame.parser->parseGrouped(frame.start, frame.active);
      frame.produced = true;
    }

    void postfixQualify(context::Context &, lexicon::Phrase &) {
      PostfixParseFrame &frame = postfixParseFrame();
      frame.result = frame.parser->parseQualification(std::move(frame.operation), std::move(frame.result));
      frame.produced = true;
    }

    void postfixCall(context::Context &, lexicon::Phrase &) {
      PostfixParseFrame &frame = postfixParseFrame();
      frame.result = frame.parser->parseCall(std::move(frame.operation), std::move(frame.result), frame.active);
      frame.produced = true;
    }

    void postfixMember(context::Context &, lexicon::Phrase &) {
      PostfixParseFrame &frame = postfixParseFrame();
      frame.result = frame.parser->parseMember(std::move(frame.operation), std::move(frame.result), frame.active);
      frame.produced = true;
    }

  } // namespace internal

  context::Value Expressions::evaluate(context::Context &context, std::string_view source) {
    return evaluate(context, source, {context.source.path, context.source.line, context.source.position});
  }

  context::Value Expressions::evaluate(context::Context &context, std::string_view source, SourceLocation origin) {
    internal::ExpressionDiagnostic diagnostic{source, std::move(origin)};
    internal::ExpressionDiagnostic *previous = internal::currentExpressionDiagnostic;
    internal::currentExpressionDiagnostic = &diagnostic;
    try {
      context::Value result = internal::Parser(context, source).parse();
      internal::currentExpressionDiagnostic = previous;
      return result;
    } catch (...) {
      internal::currentExpressionDiagnostic = previous;
      throw;
    }
  }

} // namespace recurloop
