#include <recurloop/NameInterpolation.hpp>

#include <context/Context.hpp>
#include <recurloop/Expressions.hpp>
#include <utilities/Exception.hpp>

#include <string>

namespace recurloop {
  namespace {
    char peek(context::Context &context) {
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      return context.source.buffer.bits == 0
                 ? '\0'
                 : context.source.buffer.str[context.source.buffer.offset / Byte::length];
    }

    char take(context::Context &context) {
      const char character = peek(context);
      if (character != '\0') context::Source::progress(context, Byte::length);
      return character;
    }

    [[noreturn]] void interpolationFail(const context::Context &context, Size line, Size position,
                                        const std::string &message) {
      const SourceLocation location{context.source.path, line, position};
      THROW_AT(location, "phrase name interpolation: " << message)
    }
  } // namespace

  void NameInterpolation::append(context::Context &context, lexicon::Phrase &) {
    const Size line = context.source.line;
    const Size position = context.source.position > 2 ? context.source.position - 2 : 1;
    const SourceLocation expressionOrigin{context.source.path, context.source.line, context.source.position};
    std::string expression;
    bool quoted = false;
    bool escaped = false;

    while (true) {
      const char character = take(context);
      if (character == '\0') interpolationFail(context, line, position, "unterminated '${...}'");
      if (quoted) {
        expression.push_back(character);
        if (escaped) escaped = false;
        else if (character == '\\') escaped = true;
        else if (character == '"') quoted = false;
        continue;
      }
      if (character == '"') {
        quoted = true;
        expression.push_back(character);
      } else if (character == '}') {
        break;
      } else {
        expression.push_back(character);
      }
    }

    if (expression.empty()) interpolationFail(context, line, position, "expression cannot be empty");
    const context::Value value = Expressions::evaluate(context, expression, expressionOrigin);
    if (!value.isString())
      interpolationFail(context, line, position,
                        "expression has type '" + value.typeName() + "', expected 'string'; use str(...) explicitly");
    context.workspace.key.append(value.asString());
  }
} // namespace recurloop
