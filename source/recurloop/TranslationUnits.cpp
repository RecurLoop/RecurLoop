#include <recurloop/TranslationUnits.hpp>

#include <context/Context.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/LanguageGrammar.hpp>
#include <recurloop/LexiconTransaction.hpp>
#include <recurloop/Recurloop.hpp>
#include <utilities/Exception.hpp>

#include <cctype>
#include <cstring>

namespace recurloop {
  namespace {
    constexpr std::uint64_t Magic = 0x58494E4F43455852ull; // "RXCEXONX"
    constexpr std::uint32_t Version = 1;

    struct Descriptor {
      std::uint64_t magic = Magic;
      std::uint32_t version = Version;
      std::uint32_t reserved = 0;
      std::uint64_t bytes = 0;
    };

    std::string trim(std::string value) {
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) value.erase(value.begin());
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) value.pop_back();
      return value;
    }

    lexicon::Phrase resolve(lexicon::Phrase start, std::string_view path) {
      lexicon::Phrase result = start;
      std::size_t begin = 0;
      while (begin <= path.size()) {
        const std::size_t separator = path.find(':', begin);
        std::string component = trim(std::string(path.substr(begin, separator - begin)));
        if (component.empty()) THROW(, "merge reference contains an empty path component")
        result = LanguageGrammar::find(result, component);
        if (result.isNull()) return result;
        if (separator == std::string_view::npos) break;
        begin = separator + 1;
      }
      return result;
    }

    std::string readSource(context::Context &context) {
      std::string text;
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      while (context.source.buffer.bits != 0) {
        const char character = context.source.buffer.str[context.source.buffer.offset / Byte::length];
        if (character == '\n') break;
        text.push_back(character);
        context::Source::progress(context, Byte::length);
      }
      while (context.source.buffer.bits != 0) {
        const char character = context.source.buffer.str[context.source.buffer.offset / Byte::length];
        if (!std::isspace(static_cast<unsigned char>(character))) break;
        context::Source::progress(context, Byte::length);
      }
      return trim(std::move(text));
    }
  } // namespace

  TranslationUnitRegistry::TranslationUnitRegistry(context::Context &owner) : owner(owner) {}

  TranslationUnitRegistry::~TranslationUnitRegistry() {
    std::vector<std::shared_future<std::vector<std::uint8_t>>> pending;
    {
      std::lock_guard lock(mutex);
      for (const auto &[address, job] : jobs) pending.push_back(job.result);
    }
    for (const auto &result : pending)
      if (result.valid()) {
        try {
          result.wait();
        } catch (...) {
        }
      }
  }

  std::vector<std::uint8_t> TranslationUnitRegistry::descriptor(std::string_view source) {
    Descriptor header;
    header.bytes = source.size();
    std::vector<std::uint8_t> result(sizeof(header) + source.size());
    std::memcpy(result.data(), &header, sizeof(header));
    if (!source.empty()) std::memcpy(result.data() + sizeof(header), source.data(), source.size());
    return result;
  }

  bool TranslationUnitRegistry::isDescriptor(lexicon::Phrase phrase) {
    if (phrase.isNull() || phrase.payloadSize() < sizeof(Descriptor)) return false;
    Descriptor header;
    std::memcpy(&header, phrase.content(0, sizeof(header)).toPtr(), sizeof(header));
    return header.magic == Magic && header.version == Version &&
           header.bytes == phrase.payloadSize() - sizeof(Descriptor);
  }

  std::string TranslationUnitRegistry::source(lexicon::Phrase phrase) {
    if (!isDescriptor(phrase)) THROW(, "phrase is not a source-backed lexicon")
    Descriptor header;
    std::memcpy(&header, phrase.content(0, sizeof(header)).toPtr(), sizeof(header));
    return std::string(reinterpret_cast<const char *>(phrase.content(sizeof(header), header.bytes).toPtr()),
                       header.bytes);
  }

  void TranslationUnitRegistry::start(lexicon::Phrase phrase) {
    if (!isDescriptor(phrase)) THROW(, "cannot compile a phrase which is not a lexicon descriptor")

    const Size address = phrase.getAddress();
    {
      std::lock_guard lock(mutex);
      if (jobs.contains(address)) return;
    }

    const std::string body = source(phrase);
    const std::string path = owner.source.path.empty() ? "<lexicon>" : owner.source.path;
    const std::vector<std::uint8_t> languageImage = EngineImage::encode(owner);
    auto result = std::async(std::launch::async, [body, path, languageImage]() {
                    char argument[] = "Recurloop";
                    char *arguments[] = {argument};
                    Recurloop worker;
                    worker.initializeEmbedded(1, arguments, languageImage);
                    context::Context &context = worker.getContext();
                    const Size checkpoint = context.lexicon.checkpoint().getAddress();
                    executeSource(context, body, path, 1, 1);
                    return EngineImage::encode(context, checkpoint);
                  }).share();

    std::lock_guard lock(mutex);
    jobs.try_emplace(address, Job{std::move(result)});
  }

  std::vector<std::uint8_t> TranslationUnitRegistry::image(lexicon::Phrase phrase) {
    if (!isDescriptor(phrase)) THROW(, "cannot export a phrase which is not a source-backed lexicon")
    start(phrase);

    std::shared_future<std::vector<std::uint8_t>> result;
    {
      std::lock_guard lock(mutex);
      result = jobs.at(phrase.getAddress()).result;
    }
    return result.get();
  }

  void TranslationUnitRegistry::merge(lexicon::Phrase sourcePhrase, lexicon::Phrase target) {
    LexiconTransaction transaction(owner.lexicon);
    if (!isDescriptor(sourcePhrase)) {
      EngineImage::merge(owner, sourcePhrase, target);
      transaction.commit();
      return;
    }

    EngineImage::merge(owner, image(sourcePhrase), target);
    transaction.commit();
  }

  void TranslationUnitRegistry::merge(const std::string &path, lexicon::Phrase target) {
    LexiconTransaction transaction(owner.lexicon);
    EngineImage::merge(owner, EngineImage::read(path), target);
    transaction.commit();
  }

  lexicon::Phrase TranslationUnitRegistry::reference(context::Context &context, std::string_view path) {
    const std::string normalized = trim(std::string(path));
    if (normalized.empty()) THROW(, "lexicon reference contains an empty path")
    lexicon::Phrase current =
        context.staging.dictionary.isNull() ? context.lexicon.phrase() : context.staging.dictionary;
    lexicon::Phrase result = resolve(current, normalized);
    if (result.isNull()) result = resolve(context.lexicon.phrase(), normalized);
    if (result.isNull()) THROW(, "lexicon reference names an undefined phrase: '" << normalized << "'")
    return result;
  }

  void TranslationUnitRegistry::merge(context::Context &context, lexicon::Phrase &invoked) {
    if (!context.translationUnits) context.translationUnits = std::make_shared<TranslationUnitRegistry>(context);
    const std::string source = readSource(context);
    if (source.empty()) THROW(, "merge expects a lexicon reference or image path")
    lexicon::Phrase target =
        context.staging.dictionary.isNull() ? context.lexicon.phrase() : context.staging.dictionary;
    if (source.front() == '<') {
      if (source.size() < 2 || source.back() != '>') THROW(, "merge expects one reference enclosed in '<' and '>'")
      context.translationUnits->merge(reference(context, source.substr(1, source.size() - 2)), target);
    } else {
      const context::Value value = Expressions::evaluate(context, source);
      if (!value.isString()) THROW(, "merge image path must be a string")
      if (value.asString().find('\0') != std::string::npos) THROW(, "merge image path contains a NUL byte")
      context.translationUnits->merge(value.asString(), target);
    }
    context::Lookup::leave(context, invoked, 1);
  }
} // namespace recurloop
