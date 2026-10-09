#pragma once

#include <lexicon/Phrase.hpp>
#include <utilities/Size.hpp>

#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace context {
  class Context;
}

namespace recurloop {
  // Portable help contracts are ordinary phrase dictionaries. Only their
  // attachment to an owning phrase needs a relocated sidecar reference.
  class Assistance {
  public:
    explicit Assistance(context::Context &context);
    static void attach(context::Context &context, lexicon::Phrase target, lexicon::Phrase descriptor);
    lexicon::Phrase descriptor(lexicon::Phrase target) const;
    static std::string text(lexicon::Phrase owner, std::string_view key);
    static lexicon::Phrase child(lexicon::Phrase owner, std::string_view key);
    static std::vector<lexicon::Phrase> children(lexicon::Phrase owner);

  private:
    context::Context &context;
    std::unordered_map<Size, Size> contracts;
  };
} // namespace recurloop
