#include <recurloop/TranslationUnits.hpp>

#include <context/Context.hpp>
#include <recurloop/EngineImage.hpp>
#include <recurloop/Execution.hpp>
#include <recurloop/LanguageGrammar.hpp>
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

    lexicon::Phrase readReference(context::Context &context) {
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
      text = trim(std::move(text));
      if (text.size() < 2 || text.front() != '<' || text.back() != '>')
        THROW(, "merge expects one reference enclosed in '<' and '>'")

      const std::string path = trim(text.substr(1, text.size() - 2));
      lexicon::Phrase current =
          context.staging.dictionary.isNull() ? context.lexicon.phrase() : context.staging.dictionary;
      lexicon::Phrase result = resolve(current, path);
      if (result.isNull()) result = resolve(context.lexicon.phrase(), path);
      if (result.isNull()) THROW(, "merge references an undefined phrase: '" << path << "'")
      return result;
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
    auto result = std::async(std::launch::async, [body, path]() {
                    char argument[] = "Recurloop";
                    char *arguments[] = {argument};
                    Recurloop worker;
                    worker.initialize(1, arguments);
                    context::Context &context = worker.getContext();
                    const Size checkpoint = context.lexicon.checkpoint().getAddress();
                    executeSource(context, body, path, 1, 1);
                    return EngineImage::encode(context, checkpoint);
                  }).share();

    std::lock_guard lock(mutex);
    jobs.try_emplace(address, Job{std::move(result)});
  }

  void TranslationUnitRegistry::merge(lexicon::Phrase sourcePhrase, lexicon::Phrase target) {
    const Size checkpoint = owner.lexicon.checkpoint().getAddress();
    try {
      if (!isDescriptor(sourcePhrase)) {
        EngineImage::merge(owner, sourcePhrase, target);
        return;
      }

      start(sourcePhrase);

      std::shared_future<std::vector<std::uint8_t>> result;
      {
        std::lock_guard lock(mutex);
        result = jobs.at(sourcePhrase.getAddress()).result;
      }
      const std::vector<std::uint8_t> image = result.get();
      EngineImage::merge(owner, image, target);
    } catch (...) {
      radix::Checkpoint(&owner.lexicon, checkpoint).restore();
      throw;
    }
  }

  void TranslationUnitRegistry::merge(context::Context &context, lexicon::Phrase &invoked) {
    if (!context.translationUnits) context.translationUnits = std::make_shared<TranslationUnitRegistry>(context);
    lexicon::Phrase sourcePhrase = readReference(context);
    lexicon::Phrase target =
        context.staging.dictionary.isNull() ? context.lexicon.phrase() : context.staging.dictionary;
    context.translationUnits->merge(sourcePhrase, target);
    context::Lookup::leave(context, invoked, 1);
  }
} // namespace recurloop
