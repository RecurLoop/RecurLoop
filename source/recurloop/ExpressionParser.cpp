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
            symbols(findPhrase(grammar, "symbols")), builtins(findPhrase(grammar, "builtins")),
            literals(findPhrase(grammar, "literals")),
            lexer(context, source, {symbols, prefixOperators, infixOperators}, expressionFail, {}) {
        if (grammar.isNull()) THROW(, "expression phrase grammar is not installed")
        if (prefixOperators.isNull() || infixOperators.isNull() || symbols.isNull())
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
        lexer.expect("(");
        if (lexer.accept(")")) return result;
        while (true) {
          result.push_back(expression(1, active));
          if (lexer.accept(")")) return result;
          lexer.expect(",");
        }
      }

      context::Value callNativeFunction(const Token &name, const std::vector<context::Value> &values) {
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
            lexicon::Phrase root = context.lexicon.phrase();
            lexicon::Match match =
                root.matchExact(Byte(const_cast<char *>(name.text.data())), 0, name.text.size() * Byte::length,
                                [](radix::Node *, radix::Match *candidate) -> bool {
                                  return !lexicon::Dictionary(*candidate).getPhrase().isNull();
                                });
            if (match.isNull()) expressionFail(context, name.offset, "unknown function '" + name.text + "'");
            lexicon::Phrase phrase = match.getPhrase();
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
          if (!context.language().findFunctions(name.text).empty()) return callNativeFunction(name, values);
          expressionFail(context, name.offset, "unknown function '" + name.text + "'");
        } catch (const Exception &error) {
          if (error.hasSourceLocation()) throw;
          expressionFail(context, name.offset, error.description());
        } catch (const std::exception &error) {
          expressionFail(context, name.offset, error.what());
        }
      }

      context::Value primary(bool active) {
        const Token token = lexer.take();
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
          return context::Value(value);
        }
        if (token.kind == TokenKind::Real) {
          std::string text = token.text;
          text.erase(std::remove(text.begin(), text.end(), '_'), text.end());
          double value = 0;
          const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value);
          if (error != std::errc() || end != text.data() + text.size() || !std::isfinite(value))
            expressionFail(context, token.offset, "invalid real literal");
          return context::Value(value);
        }
        if (token.kind == TokenKind::String) return context::Value(token.text);
        if (LanguageGrammar::matches(context, token.text, "(")) {
          context::Value result = expression(1, active);
          lexer.expect(")");
          return result;
        }
        if (token.kind == TokenKind::Identifier) {
          lexicon::Phrase literal = LanguageGrammar::resolve(context, literals, token.text);
          if (!literal.isNull()) return active ? invokeBuiltin(context, literal, token) : context::Value();
          if (LanguageGrammar::matches(context, lexer.current().text, "(")) {
            std::vector<context::Value> values = arguments(active);
            return active ? builtin(token, std::move(values)) : context::Value();
          }
          context::Value value;
          if (active) {
            try {
              value = context.values().get(token.text);
            } catch (const Exception &error) {
              if (error.hasSourceLocation()) throw;
              expressionFail(context, token.offset, error.description());
            }
          }
          while (lexer.accept(".")) {
            Token method = lexer.take();
            if (method.kind != TokenKind::Identifier)
              expressionFail(context, lexer.current().offset, "expected method name after '.'");
            if (!LanguageGrammar::matches(context, lexer.current().text, "("))
              expressionFail(context, method.offset, "expected '(' after method name");
            std::vector<context::Value> values = arguments(active);
            if (active) {
              values.insert(values.begin(), value);
              value = builtin(method, std::move(values));
            }
          }
          return value;
        }
        expressionFail(context, token.offset, "expected a value, variable or '('");
      }

      context::Context &context;
      lexicon::Phrase grammar;
      lexicon::Phrase prefixOperators;
      lexicon::Phrase infixOperators;
      lexicon::Phrase symbols;
      lexicon::Phrase builtins;
      lexicon::Phrase literals;
      Lexer lexer;
    };

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
