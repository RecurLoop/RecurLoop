#include <recurloop/TypeSyntax.hpp>

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/LanguageGrammar.hpp>

#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::string_view GrammarName{"\0type-syntax", 12};

    lexicon::Phrase grammarPart(context::Context &context, std::string_view name) {
      return LanguageGrammar::find(LanguageGrammar::find(context.lexicon.phrase(), GrammarName), name);
    }

    struct ParseFrame {
      context::Context *context = nullptr;
      TypeSyntax::Cursor *cursor = nullptr;
      std::string scope;
      compiler::TypeId result = compiler::InvalidType;
    };

    thread_local ParseFrame *currentParseFrame = nullptr;

    ParseFrame &frame() {
      if (currentParseFrame == nullptr) THROW(, "type syntax invoked without a parser frame")
      return *currentParseFrame;
    }

    compiler::TypeId findType(context::Context &context, const std::string &name, std::string scope) {
      compiler::TypeId result = context.language().types.find(name);
      if (result == compiler::InvalidType) result = Functions::signatureType(context, name);
      if (name.find(':') == std::string::npos) {
        while (result == compiler::InvalidType && !scope.empty()) {
          const std::string qualified = scope + ":" + name;
          result = context.language().types.find(qualified);
          if (result == compiler::InvalidType) result = Functions::signatureType(context, qualified);
          const std::size_t parent = scope.rfind(':');
          scope = parent == std::string::npos ? std::string{} : scope.substr(0, parent);
        }
      }
      return result;
    }

    compiler::TypeId resolve(context::Context &context, TypeSyntax::Cursor &cursor, const std::string &name,
                             std::string scope) {
      const compiler::TypeId result = findType(context, name, std::move(scope));
      if (result == compiler::InvalidType) cursor.typeError("unknown type '" + name + "'");
      return result;
    }

    compiler::TypeId invoke(context::Context &context, TypeSyntax::Cursor &cursor, std::string scope,
                            lexicon::Phrase syntax, compiler::TypeId initial = compiler::InvalidType) {
      ParseFrame local{&context, &cursor, std::move(scope), initial};
      ParseFrame *previous = currentParseFrame;
      currentParseFrame = &local;
      try {
        syntax.invoke(context);
      } catch (...) {
        currentParseFrame = previous;
        throw;
      }
      currentParseFrame = previous;
      if (local.result == compiler::InvalidType) cursor.typeError("type syntax did not produce a type");
      return local.result;
    }

    std::string qualified(TypeSyntax::Cursor &cursor) {
      std::string result = cursor.typeIdentifier("a type");
      while (cursor.typeAccept(":")) result += ":" + cursor.typeIdentifier("a qualified name component");
      return result;
    }

    std::string abiName(TypeSyntax::Cursor &cursor) {
      std::string result = cursor.typeIdentifier("an ABI name");
      while (cursor.typeAccept("-")) result += "-" + cursor.typeIdentifier("an ABI name component");
      return result;
    }

    void parseFunction(context::Context &, lexicon::Phrase &) {
      ParseFrame &current = frame();
      std::vector<compiler::TypeId> parameters;
      bool variadic = false;
      current.cursor->typeExpect("(");
      current.cursor->typeSkipLayout();
      if (!current.cursor->typeAccept(")")) {
        while (true) {
          if (current.cursor->typeAccept("...")) {
            variadic = true;
            current.cursor->typeSkipLayout();
            current.cursor->typeExpect(")");
            break;
          }
          parameters.push_back(TypeSyntax::parse(*current.context, *current.cursor, current.scope));
          const bool separatedByLayout = current.cursor->typeSkipLayout();
          if (current.cursor->typeAccept(")")) break;
          if (current.cursor->typeAccept(",")) {
            current.cursor->typeSkipLayout();
            continue;
          }
          if (!separatedByLayout) current.cursor->typeExpect(",");
          current.cursor->typeSkipLayout();
        }
      }
      current.cursor->typeSkipLayout();
      current.cursor->typeExpect("->");
      current.cursor->typeSkipLayout();
      const compiler::TypeId result = TypeSyntax::parse(*current.context, *current.cursor, current.scope);
      const std::string convention = current.cursor->typeAccept("abi") ? abiName(*current.cursor) : "sysv-amd64";
      current.context->language().convention(convention);
      current.result = current.context->language().types.functionOf(parameters, result, convention, variadic);
    }

    void parsePointer(context::Context &, lexicon::Phrase &) {
      ParseFrame &current = frame();
      current.result = current.context->language().types.pointerTo(current.result);
    }

    void parseArray(context::Context &, lexicon::Phrase &) {
      ParseFrame &current = frame();
      const std::size_t count = current.cursor->typeNumber("an array length");
      current.cursor->typeExpect("]");
      current.result = current.context->language().types.arrayOf(current.result, count);
    }

    lexicon::Phrase define(lexicon::Phrase owner, std::string_view key, lexicon::Phrase::Action action,
                           lexicon::Phrase type, lexicon::Phrase prototype) {
      return owner.append(std::string(key)).make(action).setType(type).setPrototype(prototype).save();
    }
  } // namespace

  void TypeSyntax::setup(context::Context &context) {
    context.actions().define("type-syntax.function", parseFunction);
    context.actions().define("type-syntax.pointer", parsePointer);
    context.actions().define("type-syntax.array", parseArray);

    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase data = lexicon::phrase::type::getData(root);
    lexicon::Phrase callable = lexicon::phrase::type::getCallable(root);
    lexicon::Phrase grammar =
        root.append(Byte(const_cast<char *>(GrammarName.data())), 0, GrammarName.size() * Byte::length)
            .make()
            .enableSubdictionary()
            .setType(data)
            .save();
    lexicon::Phrase prefix = grammar.append("prefix").make().enableSubdictionary().setType(data).save();
    lexicon::Phrase suffix = grammar.append("suffix").make().enableSubdictionary().setType(data).save();
    define(prefix, "fn", parseFunction, callable, LanguageGrammar::ensureMarker(root, "fn"));
    define(suffix, "*", parsePointer, callable, LanguageGrammar::ensureMarker(root, "*"));
    define(suffix, "[", parseArray, callable, LanguageGrammar::ensureMarker(root, "["));
  }

  compiler::TypeId TypeSyntax::parse(context::Context &context, Cursor &cursor, std::string scope) {
    lexicon::Phrase prefix = grammarPart(context, "prefix");
    lexicon::Phrase suffix = grammarPart(context, "suffix");
    if (prefix.isNull() || suffix.isNull()) cursor.typeError("type syntax grammar is unavailable");

    const std::string first(cursor.typeCurrent());
    if (first.empty()) cursor.typeError("expected a type");
    lexicon::Phrase constructor = findType(context, first, scope) == compiler::InvalidType
                                      ? LanguageGrammar::resolve(context, prefix, first)
                                      : lexicon::Phrase(&context.lexicon);
    compiler::TypeId result = compiler::InvalidType;
    if (!constructor.isNull()) {
      cursor.typeAccept(first);
      result = invoke(context, cursor, scope, constructor);
    } else {
      result = resolve(context, cursor, qualified(cursor), scope);
    }

    while (true) {
      const std::string token(cursor.typeCurrent());
      if (token.empty()) break;
      lexicon::Phrase operation = LanguageGrammar::resolve(context, suffix, token);
      if (operation.isNull()) break;
      cursor.typeAccept(token);
      result = invoke(context, cursor, scope, operation, result);
    }
    return result;
  }
} // namespace recurloop
