#pragma once

#include <cstdint>
#include <future>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include <string_view>
#include <utilities/Size.hpp>

namespace context {
  class Context;
}
namespace lexicon {
  class Phrase;
}

namespace recurloop {
  // A process-local job registry for source-backed lexicon phrases. The
  // phrase payload contains the source descriptor, while this object owns
  // only the asynchronous result and is therefore never serialized.
  class TranslationUnitRegistry {
  public:
    explicit TranslationUnitRegistry(context::Context &owner);
    ~TranslationUnitRegistry();

    void start(lexicon::Phrase phrase);
    void merge(lexicon::Phrase source, lexicon::Phrase target);
    static void merge(context::Context &context, lexicon::Phrase &invoked);

    static std::vector<std::uint8_t> descriptor(std::string_view source);
    static std::string source(lexicon::Phrase phrase);
    static bool isDescriptor(lexicon::Phrase phrase);

  private:
    struct Job {
      std::shared_future<std::vector<std::uint8_t>> result;
    };

    context::Context &owner;
    std::mutex mutex;
    std::unordered_map<Size, Job> jobs;
  };
} // namespace recurloop
