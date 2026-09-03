#pragma once

#include <utilities/Exception.hpp>

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace context {
  class Context;
}

namespace lexicon {
  class Phrase;
}

namespace recurloop {
  struct ExpandedSyntax {
    std::string source;
    std::vector<std::size_t> originalOffsets;
  };

  // Root phrases marked rewritable are the extension boundary of compiled fn
  // syntax. The same phrase can elaborate source directly and lower fn source.
  class SyntaxExtension {
  public:
    SyntaxExtension() = delete;

    static ExpandedSyntax expand(context::Context &context, std::string_view source, SourceLocation origin);
    static lexicon::Phrase dictionary(context::Context &context);
    static bool active(context::Context &context);

    static const std::uint8_t *data(context::Context &context);
    static std::uint64_t bytes(context::Context &context);
    static std::uint64_t advance(context::Context &context, std::uint64_t bytes);
    static std::uint64_t emit(context::Context &context, const std::uint8_t *source, std::uint64_t offset,
                              std::uint64_t bytes);
    static std::uint64_t copy(context::Context &context, std::uint64_t bytes);
    static std::uint64_t match(context::Context &context, std::uint64_t dictionary, std::uint64_t mode);
    static std::uint64_t elaborate(context::Context &context, std::uint64_t dictionary);
    static const std::uint8_t *path(context::Context &context);
    static std::uint64_t line(context::Context &context);
    static std::uint64_t position(context::Context &context);
  };
} // namespace recurloop
