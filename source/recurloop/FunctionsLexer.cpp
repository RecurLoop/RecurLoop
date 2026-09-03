#include "FunctionsInternal.hpp"

namespace recurloop {
  namespace function_internal {

    thread_local DiagnosticSource *currentDiagnosticSource = nullptr;

    DiagnosticScope::DiagnosticScope(std::string_view source, SourceLocation origin, std::string_view originalSource,
                                     std::span<const std::size_t> originalOffsets)
        : current{source, std::move(origin), originalSource, originalOffsets}, previous(currentDiagnosticSource) {
      currentDiagnosticSource = &current;
    }

    DiagnosticScope::~DiagnosticScope() {
      currentDiagnosticSource = previous;
    }

    lexicon::Phrase exact(lexicon::Phrase dictionary, std::string_view key) {
      return LanguageGrammar::find(dictionary, key);
    }

    char peek(context::Context &context) {
      while (context.source.buffer.bits == 0 && context.source.more) context::Source::load(context, false);
      return context.source.buffer.bits == 0 ? '\0'
                                             : context.source.buffer.str[context.source.buffer.offset / Byte::length];
    }

    std::string readLine(context::Context &context) {
      std::string result;
      while (peek(context) != '\0' && peek(context) != '\n') {
        result.push_back(peek(context));
        context::Source::progress(context, Byte::length);
      }
      return result;
    }

    std::string trim(std::string value) {
      const auto begin =
          std::find_if_not(value.begin(), value.end(), [](unsigned char character) { return std::isspace(character); });
      const auto end = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char character) {
                         return std::isspace(character);
                       }).base();
      return begin < end ? std::string(begin, end) : std::string{};
    }

    [[noreturn]] void fail(std::string_view source, std::size_t offset, const std::string &message) {
      if (currentDiagnosticSource != nullptr) {
        const std::string_view diagnosticSource = source.empty() ? currentDiagnosticSource->source : source;
        SourceLocation location;
        if (source.empty() && !currentDiagnosticSource->originalOffsets.empty()) {
          const std::size_t mapped =
              currentDiagnosticSource
                  ->originalOffsets[std::min(offset, currentDiagnosticSource->originalOffsets.size() - 1)];
          location = sourceLocationAt(currentDiagnosticSource->origin, currentDiagnosticSource->originalSource, mapped);
        } else {
          location = sourceLocationAt(currentDiagnosticSource->origin, diagnosticSource, offset);
        }
        THROW_AT(location, "fn: " << message)
      }
      const SourceLocation location = sourceLocationAt({"<input>", 1, 1}, source, offset);
      THROW_AT(location, "fn: " << message)
    }

    [[noreturn]] void lexerFail(const context::Context &, std::size_t offset, const std::string &message) {
      fail({}, offset, message);
    }

  } // namespace function_internal
} // namespace recurloop
