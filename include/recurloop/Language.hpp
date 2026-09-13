#pragma once
#include <context/Context.hpp>

#define PHRASE_CORE(Key, Action, Configure, Scope)                                                                     \
  [&]() -> auto {                                                                                                      \
    lexicon::Phrase PARENT = phrase;                                                                                   \
    lexicon::Phrase phrase = PARENT.append(Key)                                                                        \
                                 .make(Action)                                                                         \
                                 .setDefaultType(lexicon::phrase::type::getData(PARENT),                               \
                                                 lexicon::phrase::type::getElaborate(PARENT)) Configure.save();        \
    Scope;                                                                                                             \
    return phrase;                                                                                                     \
  }()
#define PHRASE_VARIADIC_ARGS(_1, _2, _3, _4, NAME, ...) NAME
#define PHRASE_2_ARGS(Key, Action) PHRASE_CORE(Key, Action, , )
#define PHRASE_3_ARGS(Key, Action, Configure) PHRASE_CORE(Key, Action, Configure, )
#define PHRASE_4_ARGS(Key, Action, Configure, Scope) PHRASE_CORE(Key, Action, .enableSubdictionary() Configure, Scope)
#define PHRASE(...) PHRASE_VARIADIC_ARGS(__VA_ARGS__, PHRASE_4_ARGS, PHRASE_3_ARGS, PHRASE_2_ARGS)(__VA_ARGS__)

#define WHITESPACES_EXCEPT_SPACE_AND_NEWLINE(...)                                                                      \
  PHRASE("\r", __VA_ARGS__);                                                                                           \
  PHRASE("\t", __VA_ARGS__);                                                                                           \
  PHRASE("\v", __VA_ARGS__);
#define WHITESPACES_EXCEPT_SPACE(...)                                                                                  \
  PHRASE("\n", __VA_ARGS__);                                                                                           \
  WHITESPACES_EXCEPT_SPACE_AND_NEWLINE(__VA_ARGS__);
#define WHITESPACES_EXCEPT_NEWLINE(...)                                                                                \
  PHRASE(" ", __VA_ARGS__);                                                                                            \
  WHITESPACES_EXCEPT_SPACE_AND_NEWLINE(__VA_ARGS__);
#define WHITESPACES(...)                                                                                               \
  PHRASE(" ", __VA_ARGS__);                                                                                            \
  WHITESPACES_EXCEPT_SPACE(__VA_ARGS__);

namespace recurloop {
  namespace language::phrases {
    inline constexpr char TYPES[] = "phrase-types";
    inline constexpr char TYPE_DATA[] = "data";
    inline constexpr char TYPE_ELABORATE[] = "elaborate";
    inline constexpr char TYPE_CALLABLE[] = "callable";
    inline constexpr char TYPE_SCOPED_CALLABLE[] = "scoped-callable";
  } // namespace language::phrases

  class Language {
  public:
    Language() = delete;

    static void setup(context::Context &context);
  };
} // namespace recurloop
