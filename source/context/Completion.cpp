#if !defined(__CONTEXT_COMPLETION_CPP)
  #define __CONTEXT_COMPLETION_CPP
  #include <context/Context.hpp>

  #include <algorithm>
  #include <utility>

namespace context {
  utilities::Completion Source::complete(Context &context, std::string_view line, std::size_t cursor) {
    CompletionRequest request;
    request.line = line;
    request.cursor = std::min(cursor, line.size());
    auto root = context.lexicon.phrase();
    auto find = [](lexicon::Phrase owner, const char *key, std::size_t length) {
      if (owner.isNull() || !owner.containsSubdictionary()) return lexicon::Phrase{};
      return owner.matchExact(Byte(const_cast<char *>(key)), 0, length * Byte::length).getPhrase();
    };
    auto provider = find(find(root, "Completion", 10), "complete", 8);
    if (provider.isNull() || !provider.isElaboratable()) return {};

    auto *previous = context.source.completion;
    context.source.completion = &request;
    try {
      // Only the library callback executes. The unfinished input remains data;
      // it is never installed as Source, elaborated, or entered into history.
      provider.elaborate(context);
    } catch (...) {
      context.source.completion = previous;
      return {};
    }
    context.source.completion = previous;
    auto &result = request.result;
    if (result.start > request.cursor) return {};
    std::sort(result.candidates.begin(), result.candidates.end());
    result.candidates.erase(std::unique(result.candidates.begin(), result.candidates.end()), result.candidates.end());
    return std::move(result);
  }
} // namespace context
#endif
