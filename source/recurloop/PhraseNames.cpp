#include <recurloop/PhraseNames.hpp>

#include <context/Context.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/NameInterpolation.hpp>
#include <utilities/Exception.hpp>

#include <cctype>
#include <string_view>

namespace recurloop {
  namespace {
    constexpr std::string_view GrammarName{"\0phrase-names", 13};
    constexpr std::string_view ExpressionsName{"\0expressions", 12};

    struct Frame {
      ParsedPhraseName result;
      std::string pendingWhitespace;
      char quote = '\0';
    };

    thread_local Frame *currentFrame = nullptr;

    Frame &frame() {
      if (currentFrame == nullptr) THROW(, "phrase-name action invoked without a parser frame")
      return *currentFrame;
    }

    lexicon::Phrase dictionary(lexicon::Phrase parent, std::string_view name) {
      return parent.append(std::string(name))
          .make()
          .enableSubdictionary()
          .setType(lexicon::phrase::type::getData(parent))
          .save();
    }

    char take(context::Context &context) {
      while (context.source.buffer.bits < Byte::length && context.source.more) context::Source::load(context, false);
      if (context.source.buffer.bits < Byte::length) THROW(, "phrase name: unexpected end of input")
      const char result = context.source.buffer.str[context.source.buffer.offset / Byte::length];
      context::Source::progress(context, Byte::length);
      return result;
    }

    bool ended(context::Context &context) {
      while (context.source.buffer.bits < Byte::length && context.source.more) context::Source::load(context, false);
      return context.source.buffer.bits < Byte::length;
    }

    void flushWhitespace(context::Context &context) {
      Frame &state = frame();
      if (!state.pendingWhitespace.empty()) {
        if (context.workspace.key.bits() != 0) context.workspace.key.append(state.pendingWhitespace);
        state.pendingWhitespace.clear();
      }
    }

    void byte(context::Context &context, lexicon::Phrase &) {
      if (frame().quote == '\0') flushWhitespace(context);
      context.workspace.key.append(take(context));
    }

    void whitespace(context::Context &, lexicon::Phrase &invoked) {
      frame().pendingWhitespace += invoked.getKey();
    }

    void beginSingle(context::Context &, lexicon::Phrase &) {
      frame().pendingWhitespace.clear();
      frame().quote = '\'';
    }

    void beginDouble(context::Context &, lexicon::Phrase &) {
      frame().pendingWhitespace.clear();
      frame().quote = '"';
    }

    void endQuote(context::Context &, lexicon::Phrase &) {
      frame().quote = '\0';
    }

    void escaped(context::Context &context, lexicon::Phrase &invoked) {
      char value = '\0';
      invoked.fetch(0, value);
      context.workspace.key.append(value);
    }

    void escapedByte(context::Context &context, lexicon::Phrase &) {
      if (frame().quote == '\0') flushWhitespace(context);
      context.workspace.key.append(take(context));
    }

    void interpolate(context::Context &context, lexicon::Phrase &invoked) {
      if (frame().quote == '\0') flushWhitespace(context);
      NameInterpolation::append(context, invoked);
    }

    void segment(context::Context &context, lexicon::Phrase &) {
      Frame &state = frame();
      state.pendingWhitespace.clear();
      const std::string value = context.workspace.key.c_str();
      if (value.empty()) THROW(, "phrase name: dictionary segment cannot be empty")
      state.result.path.push_back(value);
      context.workspace.key.clear();
    }

    void defineToken(lexicon::Phrase dictionary, std::string_view key, lexicon::Phrase::Action action) {
      dictionary.append(std::string(key)).make(action).setType(lexicon::phrase::type::getCallable(dictionary)).save();
    }

    void defineEscaped(lexicon::Phrase dictionary, std::string_view key, char value) {
      dictionary.append(std::string(key))
          .make(escaped)
          .setType(lexicon::phrase::type::getCallable(dictionary))
          .save()
          .store(value)
          .save();
    }

    void setupQuoted(lexicon::Phrase dictionary, std::string_view closing) {
      defineToken(dictionary, "", byte);
      defineToken(dictionary, "${", interpolate);
      defineToken(dictionary, "\\", escapedByte);
      defineEscaped(dictionary, "\\r", '\r');
      defineEscaped(dictionary, "\\n", '\n');
      defineEscaped(dictionary, "\\t", '\t');
      defineEscaped(dictionary, "\\v", '\v');
      defineToken(dictionary, closing, endQuote);
    }

    lexicon::Phrase assignment(context::Context &context) {
      lexicon::Phrase expressions = LanguageGrammar::find(context.lexicon.phrase(), ExpressionsName);
      return LanguageGrammar::find(expressions, "assignments");
    }

    std::string_view remainingLine(context::Context &context) {
      while (true) {
        const std::size_t offset = context.source.buffer.offset / Byte::length;
        const std::size_t bytes = context.source.buffer.bits / Byte::length;
        std::string_view source(context.source.buffer.str.data() + offset, bytes);
        const std::size_t newline = source.find_first_of("\r\n");
        if (newline != std::string_view::npos) return source.substr(0, newline);
        if (!context.source.more) return source;
        const Size previous = context.source.buffer.bits;
        context::Source::load(context, false);
        if (context.source.buffer.bits == previous) {
          const std::size_t currentOffset = context.source.buffer.offset / Byte::length;
          return std::string_view(context.source.buffer.str.data() + currentOffset,
                                  context.source.buffer.bits / Byte::length);
        }
      }
    }

    lexicon::Phrase matchAssignment(context::Context &context, lexicon::Phrase assignments) {
      const std::string_view source = remainingLine(context);
      lexicon::Phrase direct = LanguageGrammar::matchLongest(assignments, source);
      lexicon::Phrase alias = LanguageGrammar::matchLongestAlias(context, assignments, source);
      lexicon::Phrase spelling =
          direct.isNull() || (!alias.isNull() && alias.getKey().size() > direct.getKey().size()) ? alias : direct;
      if (spelling.isNull()) return spelling;
      const std::string key = spelling.getKey();
      if (!key.empty() && (std::isalnum(static_cast<unsigned char>(key.back())) || key.back() == '_') &&
          source.size() > key.size() &&
          (std::isalnum(static_cast<unsigned char>(source[key.size()])) || source[key.size()] == '_'))
        return lexicon::Phrase(&context.lexicon);
      context::Source::progress(context, key.size() * Byte::length);
      return spelling.getAddress() == alias.getAddress()
                 ? LanguageGrammar::resolve(context, assignments, spelling.getKey())
                 : spelling;
    }

    bool nameAction(lexicon::Dictionary *, lexicon::Match *candidate) {
      lexicon::Phrase phrase = candidate->getPhrase();
      return !phrase.isNull() && phrase.isInvokable();
    }
  } // namespace

  std::string ParsedPhraseName::qualified() const {
    std::string result;
    for (const std::string &segment : path) {
      if (!result.empty()) result.push_back(':');
      result += segment;
    }
    if (!result.empty()) result.push_back(':');
    result += name;
    return result;
  }

  void PhraseNames::setup(context::Context &context) {
    context.actions().define("phrase-name.byte", byte);
    context.actions().define("phrase-name.whitespace", whitespace);
    context.actions().define("phrase-name.begin-single", beginSingle);
    context.actions().define("phrase-name.begin-double", beginDouble);
    context.actions().define("phrase-name.end-quote", endQuote);
    context.actions().define("phrase-name.escaped", escaped);
    context.actions().define("phrase-name.escaped-byte", escapedByte);
    context.actions().define("phrase-name.interpolate", interpolate);
    context.actions().define("phrase-name.segment", segment);

    lexicon::Phrase root = context.lexicon.phrase();
    lexicon::Phrase grammar =
        root.append(Byte(const_cast<char *>(GrammarName.data())), 0, GrammarName.size() * Byte::length)
            .make()
            .enableSubdictionary()
            .setType(lexicon::phrase::type::getData(root))
            .save();
    lexicon::Phrase plain = dictionary(grammar, "plain");
    lexicon::Phrase single = dictionary(grammar, "single");
    lexicon::Phrase doubleQuoted = dictionary(grammar, "double");

    defineToken(plain, "", byte);
    defineToken(plain, "${", interpolate);
    defineToken(plain, "\\", escapedByte);
    defineEscaped(plain, "\\r", '\r');
    defineEscaped(plain, "\\n", '\n');
    defineEscaped(plain, "\\t", '\t');
    defineEscaped(plain, "\\v", '\v');
    defineToken(plain, "'", beginSingle);
    defineToken(plain, "\"", beginDouble);
    defineToken(plain, ":", segment);
    for (std::string_view character : {" ", "\r", "\n", "\t", "\v"}) defineToken(plain, character, whitespace);

    setupQuoted(single, "'");
    setupQuoted(doubleQuoted, "\"");
  }

  ParsedPhraseName PhraseNames::parseAssignment(context::Context &context, bool allowEmpty,
                                                bool allowMissingOperation) {
    lexicon::Phrase grammar = LanguageGrammar::find(context.lexicon.phrase(), GrammarName);
    lexicon::Phrase plain = LanguageGrammar::find(grammar, "plain");
    lexicon::Phrase single = LanguageGrammar::find(grammar, "single");
    lexicon::Phrase doubleQuoted = LanguageGrammar::find(grammar, "double");
    lexicon::Phrase assignments = assignment(context);
    if (plain.isNull() || single.isNull() || doubleQuoted.isNull() || assignments.isNull())
      THROW(, "phrase-name grammar is not initialized")

    Frame state;
    Frame *previous = currentFrame;
    currentFrame = &state;
    context.workspace.key.clear();
    try {
      while (true) {
        if (state.quote == '\0') {
          lexicon::Phrase operation = matchAssignment(context, assignments);
          if (!operation.isNull()) {
            state.pendingWhitespace.clear();
            state.result.name = context.workspace.key.c_str();
            state.result.operation = operation;
            if (state.result.name.empty() && !allowEmpty) THROW(, "phrase name cannot be empty")
            currentFrame = previous;
            return state.result;
          }
          if (allowMissingOperation && ended(context)) {
            state.pendingWhitespace.clear();
            state.result.name = context.workspace.key.c_str();
            if (state.result.name.empty() && !allowEmpty) THROW(, "phrase name cannot be empty")
            currentFrame = previous;
            return state.result;
          }
        }

        lexicon::Phrase mode = state.quote == '\'' ? single : state.quote == '"' ? doubleQuoted : plain;
        lexicon::Dictionary tokens = mode.getSubdictionary();
        lexicon::Phrase token = context::Source::matchLongest(context, tokens, nameAction, false);
        if (token.isNull()) THROW(, "phrase name: cannot match the next source byte")
        token.invoke(context);
      }
    } catch (...) {
      currentFrame = previous;
      throw;
    }
  }
} // namespace recurloop
