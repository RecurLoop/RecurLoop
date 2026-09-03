#include <recurloop/PhraseDefinition.hpp>

#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/SyntaxCursor.hpp>
#include <utilities/Exception.hpp>

#include <cctype>
#include <string>
#include <string_view>

namespace recurloop {
  namespace {
    constexpr std::string_view FieldGrammarName{"\0phrase-fields", 14};

    [[noreturn]] void mutationSyntaxError(const context::Context &context, std::size_t offset,
                                          const std::string &message) {
      const SourceLocation location{context.source.path, context.source.line, context.source.position + offset};
      THROW_AT(location, "phrase mutation: " << message)
    }

    std::string trim(std::string value) {
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) value.erase(value.begin());
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) value.pop_back();
      return value;
    }

    lexicon::Phrase reference(context::Context &context, const std::string &source) {
      if (source.size() < 2 || source.front() != '<' || source.back() != '>')
        THROW(, "phrase field expects a reference enclosed in '<' and '>'")
      std::string path = trim(source.substr(1, source.size() - 2));
      lexicon::Phrase phrase = context.lexicon.phrase();
      std::size_t begin = 0;
      while (true) {
        const std::size_t end = path.find(':', begin);
        const std::string key = trim(path.substr(begin, end - begin));
        if (key.empty()) THROW(, "phrase field contains an empty reference component")
        phrase = LanguageGrammar::find(phrase, key);
        if (phrase.isNull()) THROW(, "phrase field references an undefined phrase: '" << path << "'")
        if (end == std::string::npos) return phrase;
        begin = end + 1;
      }
    }

    class Parser;

    struct FieldFrame {
      Parser *parser = nullptr;
      lexicon::Phrase *target = nullptr;
    };

    thread_local FieldFrame *currentFieldFrame = nullptr;

    FieldFrame &fieldFrame() {
      if (currentFieldFrame == nullptr) THROW(, "phrase field invoked without a parser frame")
      return *currentFieldFrame;
    }

    class Parser {
    public:
      struct InlineFunction {
        std::string signature;
        std::string body;
        std::size_t signatureOffset = 0;
        std::size_t bodyOffset = 0;
      };

      Parser(context::Context &context, std::string_view source, SourceLocation origin)
          : context(context), source(source), origin(std::move(origin)) {}

      void parse() {
        while (true) {
          skip();
          if (cursor == source.size()) return;
          const std::size_t fieldOffset = cursor;
          const std::string field = identifier();
          skip();
          expect('=');
          skip();
          lexicon::Phrase fields = LanguageGrammar::find(context.lexicon.phrase(), FieldGrammarName);
          lexicon::Phrase syntax = LanguageGrammar::resolve(context, fields, field);
          if (syntax.isNull()) fail("unknown field '" + field + "'", fieldOffset);
          apply(syntax);
          skip();
          if (!accept(",")) accept(";");
        }
      }

      void apply(lexicon::Phrase syntax, lexicon::Phrase *target = nullptr) {
        FieldFrame frame{this, target};
        FieldFrame *previous = currentFieldFrame;
        currentFieldFrame = &frame;
        try {
          syntax.invoke(context);
        } catch (const Exception &error) {
          currentFieldFrame = previous;
          if (error.hasSourceLocation()) throw;
          fail(error.description());
        } catch (const std::exception &error) {
          currentFieldFrame = previous;
          fail(error.what());
        } catch (...) {
          currentFieldFrame = previous;
          fail("unknown internal error");
        }
        currentFieldFrame = previous;
      }

      void finish() {
        skip();
        if (cursor != source.size()) fail("unexpected text after field value");
      }

      void applyDictionary(lexicon::Phrase *target) {
        if (target != nullptr) THROW(, "phrase dictionary cannot be changed after creation")
        if (boolean()) context.staging.phrase.enableSubdictionary();
      }

      void applySerializable(lexicon::Phrase *target) {
        const bool value = boolean();
        if (target != nullptr) {
          target->setSerializable(value).save();
          return;
        }
        context.exec.pendingPhraseSerializable = value;
        context.exec.hasPendingPhraseSerializable = true;
      }

      void applyPermanent(lexicon::Phrase *target) {
        const bool value = boolean();
        if (target != nullptr) {
          target->setPermanent(value).save();
          return;
        }
        context.exec.pendingPhrasePermanent = value;
        context.exec.hasPendingPhrasePermanent = true;
      }

      void applyRewrite(lexicon::Phrase *target) {
        const bool value = boolean();
        if (target != nullptr) {
          target->setRewritable(value).save();
          return;
        }
        context.exec.pendingPhraseRewritable = value;
        context.exec.hasPendingPhraseRewritable = true;
      }

      void applyPayload(lexicon::Phrase *target) {
        if (target != nullptr) THROW(, "phrase payload cannot be changed after creation")
        const std::string value = string();
        context.exec.pendingPhrasePayload.assign(value.begin(), value.end());
      }

      lexicon::Phrase referenceValue() {
        return accept("none") ? lexicon::Phrase(&context.lexicon) : reference(context, referenceText());
      }

      void applyType(lexicon::Phrase *target) {
        lexicon::Phrase value = referenceValue();
        if (target != nullptr)
          target->setType(value).save();
        else
          context.staging.phrase.setType(value);
      }

      void applyPrototype(lexicon::Phrase *target) {
        lexicon::Phrase value = referenceValue();
        if (target != nullptr)
          target->setPrototype(value).save();
        else
          context.staging.phrase.setPrototype(value);
      }

      void applySuccessor(lexicon::Phrase *target) {
        lexicon::Phrase value = referenceValue();
        if (target != nullptr)
          target->setSuccessor(value).save();
        else
          context.staging.phrase.setSuccessor(value);
      }

      void applyAction(lexicon::Phrase *target) {
        if (accept("fn")) {
          if (target != nullptr) THROW(, "inline phrase action can only be allocated during creation")
          const InlineFunction functionSource = function();
          const SourceLocation signatureOrigin = sourceLocationAt(origin, source, functionSource.signatureOffset);
          const SourceLocation bodyOrigin = sourceLocationAt(origin, source, functionSource.bodyOffset);
          Functions::bindAction(context.staging.phrase,
                                Functions::compileAction(context, functionSource.signature, functionSource.body, {},
                                                         signatureOrigin, bodyOrigin));
          return;
        }
        lexicon::Phrase value = referenceValue();
        if (target != nullptr) {
          target->setAction(value.getAction());
          lexicon::Phrase implementation = value.getActionImplementation();
          if (!implementation.isNull()) target->setActionImplementation(implementation);
          target->save();
          return;
        }
        context.staging.phrase.setAction(value.getAction());
        lexicon::Phrase implementation = value.getActionImplementation();
        if (!implementation.isNull()) context.staging.phrase.setActionImplementation(implementation);
      }

      void applyParent(lexicon::Phrase *) {
        THROW(, "phrase parent is immutable")
      }

      void skip() {
        while (cursor < source.size()) {
          if (std::isspace(static_cast<unsigned char>(source[cursor]))) {
            ++cursor;
            continue;
          }
          if (source.substr(cursor).starts_with("//")) {
            cursor += 2;
            while (cursor < source.size() && source[cursor] != '\n') ++cursor;
            continue;
          }
          if (source.substr(cursor).starts_with("/*")) {
            cursor += 2;
            while (cursor + 1 < source.size() && !source.substr(cursor).starts_with("*/")) ++cursor;
            if (cursor + 1 >= source.size()) fail("unterminated block comment");
            cursor += 2;
            continue;
          }
          return;
        }
      }
      bool accept(std::string_view value) {
        std::string spelling;
        if (source.substr(cursor).starts_with(value)) {
          spelling = std::string(value);
        } else {
          lexicon::Phrase root = context.lexicon.phrase();
          lexicon::Phrase matched = LanguageGrammar::matchLongest(root, source.substr(cursor));
          lexicon::Phrase canonical = LanguageGrammar::find(root, value);
          if (matched.isNull() || canonical.isNull() || !LanguageGrammar::inherits(matched, canonical)) return false;
          spelling = matched.getKey();
        }
        const std::size_t end = cursor + spelling.size();
        if (!spelling.empty() &&
            (std::isalnum(static_cast<unsigned char>(spelling.back())) || spelling.back() == '_') &&
            end < source.size() && (std::isalnum(static_cast<unsigned char>(source[end])) || source[end] == '_'))
          return false;
        cursor = end;
        return true;
      }
      void expect(char value) {
        if (!accept(std::string_view(&value, 1))) fail("expected '" + std::string(1, value) + "'");
      }
      std::string identifier() {
        const std::size_t begin = cursor;
        while (cursor < source.size() &&
               (std::isalnum(static_cast<unsigned char>(source[cursor])) || source[cursor] == '_'))
          ++cursor;
        if (begin == cursor) fail("expected a field name");
        return std::string(source.substr(begin, cursor - begin));
      }
      bool boolean() {
        const std::string value = identifier();
        if (LanguageGrammar::matches(context, value, "true")) return true;
        if (LanguageGrammar::matches(context, value, "false")) return false;
        THROW(, "phrase boolean field expects true or false")
      }
      std::string referenceText() {
        if (cursor == source.size() || source[cursor] != '<') THROW(, "phrase definition expects a reference")
        const std::size_t begin = cursor++;
        while (cursor < source.size() && source[cursor] != '>') ++cursor;
        if (cursor == source.size()) THROW(, "unterminated phrase reference")
        ++cursor;
        return std::string(source.substr(begin, cursor - begin));
      }
      std::string string() {
        expect('"');
        std::string result;
        while (cursor < source.size()) {
          char value = source[cursor++];
          if (value == '"') return result;
          if (value != '\\') {
            result.push_back(value);
            continue;
          }
          if (cursor == source.size()) break;
          switch (source[cursor++]) {
          case 'n': result.push_back('\n'); break;
          case 'r': result.push_back('\r'); break;
          case 't': result.push_back('\t'); break;
          case '0': result.push_back('\0'); break;
          case '\\': result.push_back('\\'); break;
          case '"': result.push_back('"'); break;
          default: THROW(, "unsupported phrase payload escape")
          }
        }
        THROW(, "unterminated phrase payload")
      }

      InlineFunction function() {
        skip();
        const std::size_t signatureBegin = cursor;
        while (cursor < source.size() && source[cursor] != '{') ++cursor;
        if (cursor == source.size()) THROW(, "inline phrase action expects a function body")
        const std::string signature = trim(std::string(source.substr(signatureBegin, cursor - signatureBegin)));
        ++cursor;
        const std::size_t bodyBegin = cursor;
        std::size_t depth = 1;
        while (cursor < source.size()) {
          if (source.substr(cursor).starts_with("//")) {
            cursor += 2;
            while (cursor < source.size() && source[cursor] != '\n') ++cursor;
            continue;
          }
          if (source.substr(cursor).starts_with("/*")) {
            cursor += 2;
            while (cursor + 1 < source.size() && !source.substr(cursor).starts_with("*/")) ++cursor;
            if (cursor + 1 >= source.size()) THROW(, "unterminated inline action comment")
            cursor += 2;
            continue;
          }
          if (source[cursor] == '"') {
            ++cursor;
            while (cursor < source.size() && source[cursor] != '"') {
              if (source[cursor] == '\\' && cursor + 1 < source.size())
                cursor += 2;
              else
                ++cursor;
            }
            if (cursor == source.size()) THROW(, "unterminated inline action string")
            ++cursor;
            continue;
          }
          if (source[cursor] == '{') {
            ++depth;
            ++cursor;
            continue;
          }
          if (source[cursor] == '}') {
            --depth;
            if (depth == 0) {
              const std::string body(source.substr(bodyBegin, cursor - bodyBegin));
              ++cursor;
              return {signature, body, signatureBegin, bodyBegin};
            }
          }
          ++cursor;
        }
        THROW(, "unterminated inline phrase action")
      }

      context::Context &context;
      std::string_view source;
      SourceLocation origin;
      std::size_t cursor = 0;

      [[noreturn]] void fail(const std::string &message, std::size_t offset = std::string_view::npos) const {
        if (offset == std::string_view::npos) offset = cursor;
        const SourceLocation location = sourceLocationAt(origin, source, offset);
        THROW_AT(location, "phrase definition: " << message)
      }
    };

    void fieldDictionary(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyDictionary(frame.target);
    }

    void fieldSerializable(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applySerializable(frame.target);
    }

    void fieldPermanent(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyPermanent(frame.target);
    }

    void fieldRewrite(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyRewrite(frame.target);
    }

    void fieldPayload(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyPayload(frame.target);
    }

    void fieldType(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyType(frame.target);
    }

    void fieldPrototype(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyPrototype(frame.target);
    }

    void fieldSuccessor(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applySuccessor(frame.target);
    }

    void fieldAction(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyAction(frame.target);
    }

    void fieldParent(context::Context &, lexicon::Phrase &) {
      FieldFrame &frame = fieldFrame();
      frame.parser->applyParent(frame.target);
    }
  } // namespace

  void PhraseDefinition::setup(context::Context &context) {
    context.actions().define("phrase.field.dictionary", fieldDictionary);
    context.actions().define("phrase.field.serializable", fieldSerializable);
    context.actions().define("phrase.field.permanent", fieldPermanent);
    context.actions().define("phrase.field.rewrite", fieldRewrite);
    context.actions().define("phrase.field.payload", fieldPayload);
    context.actions().define("phrase.field.type", fieldType);
    context.actions().define("phrase.field.prototype", fieldPrototype);
    context.actions().define("phrase.field.successor", fieldSuccessor);
    context.actions().define("phrase.field.action", fieldAction);
    context.actions().define("phrase.field.parent", fieldParent);

    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase callable = lexicon::phrase::type::getCallable(root);
    for (std::string_view token : {"=", ",", ";", "none"}) LanguageGrammar::ensureMarker(root, token);
    lexicon::Phrase fields =
        root.append(Byte(const_cast<char *>(FieldGrammarName.data())), 0, FieldGrammarName.size() * Byte::length)
            .make()
            .enableSubdictionary()
            .setType(lexicon::phrase::type::getData(root))
            .save();
    const auto define = [&](std::string name, lexicon::Phrase::Action action) {
      lexicon::Phrase marker = LanguageGrammar::ensureMarker(root, name);
      fields.append(std::move(name)).make(action).setType(callable).setPrototype(marker).save();
    };
    define("dictionary", fieldDictionary);
    define("serializable", fieldSerializable);
    define("permanent", fieldPermanent);
    define("rewrite", fieldRewrite);
    define("payload", fieldPayload);
    define("type", fieldType);
    define("prototype", fieldPrototype);
    define("successor", fieldSuccessor);
    define("action", fieldAction);
    define("parent", fieldParent);
  }

  void PhraseDefinition::define(context::Context &context, lexicon::Phrase &invoked) {
    SourceBlock block = Blocks::capture(context);
    if (!trim(std::move(block.header)).empty()) THROW(, "phrase expects '{' immediately after the keyword")
    context.exec.pendingPhrasePayload.clear();
    context.exec.hasPendingPhraseSerializable = false;
    context.exec.hasPendingPhrasePermanent = false;
    context.exec.hasPendingPhraseRewritable = false;
    try {
      Parser(context, block.body, {block.path, block.line, block.position}).parse();
    } catch (...) {
      context.exec.pendingPhrasePayload.clear();
      context.exec.hasPendingPhraseSerializable = false;
      context.exec.hasPendingPhrasePermanent = false;
      context.exec.hasPendingPhraseRewritable = false;
      throw;
    }
    context::Lookup::leave(context, invoked);
  }

  bool PhraseDefinition::mutate(context::Context &context) {
    const std::size_t offset = context.source.buffer.offset / Byte::length;
    const std::size_t bytes = context.source.buffer.bits / Byte::length;
    if (offset > context.source.buffer.str.size() || bytes > context.source.buffer.str.size() - offset) return false;
    std::string source = context.source.buffer.str.substr(offset, bytes);
    const std::size_t newline = source.find_first_of("\r\n");
    if (newline != std::string::npos) source.resize(newline);

    lexicon::Phrase root = context.lexicon.phrase();
    SyntaxCursor cursor(context, source, {root}, mutationSyntaxError, {.bareWords = true});
    if (cursor.current().kind == SyntaxTokenKind::End) return false;

    std::string path = cursor.take().text;
    while (cursor.accept(":")) {
      if (cursor.current().kind == SyntaxTokenKind::End) return false;
      path += ':' + cursor.take().text;
    }
    if (!cursor.accept(".")) return false;
    if (cursor.current().kind == SyntaxTokenKind::End) return false;
    const std::string field = cursor.take().text;
    if (!cursor.accept("=")) return false;
    if (cursor.current().kind == SyntaxTokenKind::End) {
      const SourceLocation location{context.source.path, context.source.line,
                                    context.source.position + cursor.current().offset};
      THROW_AT(location, "phrase mutation requires a value")
    }
    std::size_t valueOffset = cursor.current().offset;
    while (valueOffset < source.size() && std::isspace(static_cast<unsigned char>(source[valueOffset]))) ++valueOffset;
    const std::string value = trim(source.substr(valueOffset));
    if (value.empty()) {
      const SourceLocation location{context.source.path, context.source.line,
                                    context.source.position + cursor.current().offset};
      THROW_AT(location, "phrase mutation requires a value")
    }

    lexicon::Phrase phrase = reference(context, '<' + path + '>');
    if (phrase.isPermanent()) {
      const SourceLocation location{context.source.path, context.source.line, context.source.position};
      THROW_AT(location, "Cannot modify permanent phrase '" << phrase.getKeyEscaped() << "'.")
    }
    lexicon::Phrase syntax =
        LanguageGrammar::resolve(context, LanguageGrammar::find(context.lexicon.phrase(), FieldGrammarName), field);
    if (syntax.isNull()) {
      const SourceLocation location{context.source.path, context.source.line,
                                    context.source.position + cursor.current().offset};
      THROW_AT(location, "unknown phrase field '" << field << "'")
    }
    Parser parser(context, value, {context.source.path, context.source.line, context.source.position + valueOffset});
    parser.apply(syntax, &phrase);
    parser.finish();
    context::Source::progress(context, source.size() * Byte::length);
    return true;
  }
} // namespace recurloop
