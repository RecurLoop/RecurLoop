#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>
#include <utilities/Completion.hpp>
#include <cstdint>

namespace context {
  class Source {
  public:
    std::string path = "";
    Size line = 1;
    Size position = 1;
    bool more = true;

    struct Buffer {
      std::string str = "";
      Size match = 0;
      Size offset = 0;
      Size bits = 0;
    } buffer;

    // A completion request is transport scratch state. It never enters an
    // engine image; libraries receive it through the generic Context API.
    struct CompletionRequest {
      std::string line;
      std::size_t cursor = 0;
      utilities::Completion result;
      std::string candidate;
      std::uint64_t data = 0;
    };
    CompletionRequest *completion = nullptr;

    DECLARATION static utilities::Completion complete(Context &context, std::string_view line, std::size_t cursor);

    DECLARATION static void load(Context &context, bool slide = false);
    DECLARATION static void progress(Context &context, Size bits);

    DECLARATION static lexicon::Phrase matchFirst(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide);
    DECLARATION static lexicon::Phrase matchLongest(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide);
    DECLARATION static lexicon::Phrase matchExact(Context &context, lexicon::Dictionary &dictionary, lexicon::match::Filter filter, bool slide);
  };
} // namespace context
