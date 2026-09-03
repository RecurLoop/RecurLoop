#include <recurloop/ContextApi.hpp>
#include <recurloop/BitString.hpp>
#include <recurloop/Blocks.hpp>
#include <recurloop/Expressions.hpp>
#include <recurloop/Functions.hpp>
#include <recurloop/PhraseAction.hpp>
#include <recurloop/SyntaxExtension.hpp>

#include <compiler/DynamicLinker.hpp>
#include <compiler/LanguageState.hpp>
#include <context/Context.hpp>
#include <lexicon/Lexicon.hpp>
#include <radix/Checkpoint.hpp>

#include <algorithm>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <exception>
#include <limits>
#include <string>
#include <string_view>
#include <unordered_set>
#include <utility>
#include <vector>

namespace recurloop {
  namespace {
    constexpr std::string_view FindPhrase{"context:phrase:find"};
    constexpr std::string_view DefinePhrase{"context:phrase:define"};
    constexpr std::string_view DefinePhraseAlias{"context:phrase:define:alias"};
    constexpr std::string_view CallPhrase{"context:phrase:call"};
    constexpr std::string_view GetPhrase{"context:phrase:get"};
    constexpr std::string_view SetPhrase{"context:phrase:set"};
    constexpr std::string_view DataPhrase{"context:phrase:data"};
    constexpr std::string_view KeyPhrase{"context:phrase:key"};
    constexpr std::string_view ReadPhrase{"context:phrase:read"};
    constexpr std::string_view ChildPhrase{"context:phrase:child"};
    constexpr std::string_view SourceEnsure{"context:source:ensure"};
    constexpr std::string_view SourceData{"context:source:data"};
    constexpr std::string_view SourceBytes{"context:source:bytes"};
    constexpr std::string_view SourcePeek{"context:source:peek"};
    constexpr std::string_view SourceAdvance{"context:source:advance"};
    constexpr std::string_view SourceMatch{"context:source:match"};
    constexpr std::string_view SourceRoot{"context:source:root"};
    constexpr std::string_view SyntaxDictionary{"context:syntax:dictionary"};
    constexpr std::string_view SyntaxActive{"context:syntax:active"};
    constexpr std::string_view SyntaxData{"context:syntax:data"};
    constexpr std::string_view SyntaxBytes{"context:syntax:bytes"};
    constexpr std::string_view SyntaxAdvance{"context:syntax:advance"};
    constexpr std::string_view SyntaxEmit{"context:syntax:emit"};
    constexpr std::string_view SyntaxCopy{"context:syntax:copy"};
    constexpr std::string_view SyntaxMatch{"context:syntax:match"};
    constexpr std::string_view SyntaxElaborate{"context:syntax:elaborate"};
    constexpr std::string_view SyntaxPath{"context:syntax:path"};
    constexpr std::string_view SyntaxLine{"context:syntax:line"};
    constexpr std::string_view SyntaxPosition{"context:syntax:position"};
    constexpr std::string_view BlockCapture{"context:source:block:capture"};
    constexpr std::string_view BlockHeader{"context:source:block:header"};
    constexpr std::string_view BlockBody{"context:source:block:body"};
    constexpr std::string_view BlockPath{"context:source:block:path"};
    constexpr std::string_view BlockHeaderLine{"context:source:block:header:line"};
    constexpr std::string_view BlockHeaderPosition{"context:source:block:header:position"};
    constexpr std::string_view BlockLine{"context:source:block:line"};
    constexpr std::string_view BlockPosition{"context:source:block:position"};
    constexpr std::string_view BlockExecute{"context:source:block:execute"};
    constexpr std::string_view BlockRelease{"context:source:block:release"};
    constexpr std::string_view DiagnosticError{"context:diagnostic:error"};
    constexpr std::string_view DiagnosticErrorAt{"context:diagnostic:error:at"};
    constexpr std::string_view ExpressionFormat{"context:expression:format"};
    constexpr std::string_view ExpressionFormatAt{"context:expression:format:at"};
    constexpr std::string_view ValueContains{"context:value:contains"};
    constexpr std::string_view ValueFormat{"context:value:format"};
    constexpr std::string_view ValueDefineText{"context:value:define:text"};
    constexpr std::string_view ValueDefineInteger{"context:value:define:integer"};
    constexpr std::string_view ValueAssignText{"context:value:assign:text"};
    constexpr std::string_view ValueAssignInteger{"context:value:assign:integer"};
    constexpr std::string_view TypeFind{"context:type:find"};
    constexpr std::string_view TypeGet{"context:type:get"};
    constexpr std::string_view TypeInteger{"context:type:integer"};
    constexpr std::string_view TypeFloating{"context:type:floating"};
    constexpr std::string_view TypePointer{"context:type:pointer"};
    constexpr std::string_view TypeArray{"context:type:array"};
    constexpr std::string_view TypeDeclareStructure{"context:type:structure:declare"};
    constexpr std::string_view TypeCompleteStructure{"context:type:structure:complete"};
    constexpr std::string_view TypeFunction{"context:type:function"};

    template <typename Result, typename Operation>
    Result checked(context::Context *context, Result failure, Operation &&operation) noexcept {
      if (context == nullptr || context->exec.pendingException) return failure;
      try {
        return operation(*context);
      } catch (...) {
        context->exec.pendingException = std::current_exception();
        return failure;
      }
    }

    bool validByteSlice(const std::uint8_t *text, std::uint64_t offset, std::uint64_t bytes) {
      return (text != nullptr || bytes == 0) && offset <= std::numeric_limits<Size>::max() / Byte::length &&
             bytes <= std::numeric_limits<Size>::max() / Byte::length - offset;
    }

    bool validBitSlice(const std::uint8_t *text, std::uint64_t offset, std::uint64_t bits) {
      return (text != nullptr || bits == 0) && offset <= std::numeric_limits<Size>::max() &&
             bits <= std::numeric_limits<Size>::max() - offset;
    }

    bool bitView(const BitString *text, std::uint64_t offset, std::uint64_t bits, const std::uint8_t *&data) {
      if (text == nullptr || (text->data == nullptr && text->bits != 0) || offset > text->bits ||
          bits > text->bits - offset || !validBitSlice(text->data, offset, bits))
        return false;
      data = text->data;
      return true;
    }

    std::uint8_t *ownedText(std::string_view value) {
      auto *result = static_cast<std::uint8_t *>(std::malloc(value.size() + 1));
      if (result == nullptr) THROW(, "context text allocation failed")
      if (!value.empty()) std::memcpy(result, value.data(), value.size());
      result[value.size()] = 0;
      return result;
    }

    lexicon::Phrase phraseAt(context::Context &context, std::uint64_t address) {
      if (address == 0 || address >= context.lexicon.memoryUsed()) return lexicon::Phrase(&context.lexicon);
      return lexicon::Phrase(&context.lexicon, address).load();
    }

    lexicon::Phrase ownerAt(context::Context &context, std::uint64_t address) {
      return address == 0 ? context.lexicon.phrase() : phraseAt(context, address);
    }

    bool validAction(const PhraseAction *action) {
      return action != nullptr && (action->symbol != nullptr || action->bytes == 0) && action->bytes != 0;
    }

    lexicon::Phrase inlineAction(context::Context &context, const PhraseAction *action) {
      if (!validAction(action)) THROW(, "inline phrase action descriptor is invalid")
      const std::string symbol(reinterpret_cast<const char *>(action->symbol), action->bytes);
      if (!context.language().findFunction(symbol) || !context.language().findModule(symbol))
        THROW(, "inline phrase action is unavailable: '" << symbol << "'")
      return Functions::action(context, symbol);
    }

    void copyAction(lexicon::Draft &draft, lexicon::Phrase action) {
      draft.setAction(action.getAction());
      lexicon::Phrase implementation = action.getActionImplementation();
      if (!implementation.isNull()) draft.setActionImplementation(implementation);
    }

    void copyAction(lexicon::Phrase &phrase, lexicon::Phrase action) {
      phrase.setAction(action.getAction());
      lexicon::Phrase implementation = action.getActionImplementation();
      if (!implementation.isNull()) phrase.setActionImplementation(implementation);
    }

    auto populated() {
      return
          [](radix::Node *, radix::Match *candidate) { return !lexicon::Dictionary(*candidate).getPhrase().isNull(); };
    }

    std::uint64_t sourceAvailable(context::Context &context, std::uint64_t requested) {
      while (context.source.buffer.bits / Byte::length < requested && context.source.more)
        context::Source::load(context, false);
      return context.source.buffer.bits / Byte::length;
    }

    std::uint64_t findPhrase(context::Context *context, std::uint64_t ownerAddress, const std::uint8_t *text,
                             std::uint64_t offset, std::uint64_t bits, std::uint64_t mode) noexcept {
      if (context == nullptr || !validBitSlice(text, offset, bits)) return 0;
      try {
        lexicon::Phrase owner = ownerAt(*context, ownerAddress);
        if (owner.isNull() || !owner.containsSubdictionary()) return 0;
        lexicon::Match match;
        if (mode == context_phrase::First)
          match = owner.matchFirst(Byte(const_cast<std::uint8_t *>(text)), offset, bits, populated());
        else if (mode == context_phrase::Longest)
          match = owner.matchLongest(Byte(const_cast<std::uint8_t *>(text)), offset, bits, populated());
        else if (mode == context_phrase::Exact)
          match = owner.matchExact(Byte(const_cast<std::uint8_t *>(text)), offset, bits, populated());
        else
          return 0;
        return match.isNull() ? 0 : match.getPhrase().getAddress();
      } catch (...) {
        return 0;
      }
    }

    std::uint64_t definePhrase(context::Context *context, std::uint64_t ownerAddress, const std::uint8_t *text,
                               std::uint64_t offset, std::uint64_t bits, std::uint64_t typeAddress,
                               std::uint64_t prototypeAddress, std::uint64_t successorAddress,
                               std::uint64_t actionAddress, const PhraseAction *actionValue,
                               std::uint64_t flags) noexcept {
      if (context == nullptr || !validBitSlice(text, offset, bits)) return 0;
      if (actionValue != nullptr && !(flags & context_phrase::HasAction)) return 0;
      const Size checkpoint = context->lexicon.checkpoint().getAddress();
      try {
        lexicon::Phrase owner = ownerAt(*context, ownerAddress);
        if (owner.isNull() || !owner.containsSubdictionary()) return 0;
        const auto optional = [&](std::uint64_t address, std::uint64_t present) {
          if (!(flags & present) || address == 0) return lexicon::Phrase(&context->lexicon);
          lexicon::Phrase phrase = phraseAt(*context, address);
          if (phrase.isNull()) THROW(, "context phrase definition references an invalid phrase")
          return phrase;
        };
        lexicon::Phrase type = optional(typeAddress, context_phrase::HasType);
        lexicon::Phrase prototype = optional(prototypeAddress, context_phrase::HasPrototype);
        lexicon::Phrase successor = optional(successorAddress, context_phrase::HasSuccessor);
        lexicon::Phrase action = actionValue == nullptr ? optional(actionAddress, context_phrase::HasAction)
                                                        : inlineAction(*context, actionValue);
        lexicon::Draft draft = owner.append(Byte(const_cast<std::uint8_t *>(text)), offset, bits).make();
        draft.setParent(owner);
        if (flags & context_phrase::Dictionary) draft.enableSubdictionary();
        if (flags & context_phrase::HasType) draft.setType(type);
        if (flags & context_phrase::HasPrototype) draft.setPrototype(prototype);
        if (flags & context_phrase::HasSuccessor) draft.setSuccessor(successor);
        if (flags & context_phrase::HasAction) {
          if (actionValue == nullptr)
            copyAction(draft, action);
          else
            Functions::bindAction(draft, action);
        }
        lexicon::Phrase &saved = draft.save();
        if (flags & context_phrase::Unserializable)
          saved.setSerializable(false).save();
        else if (flags & context_phrase::Serializable)
          saved.setSerializable(true).save();
        if (flags & context_phrase::Rewritable) saved.setRewritable(true).save();
        if (flags & context_phrase::Permanent) saved.setPermanent(true).save();
        return saved.getAddress();
      } catch (...) {
        radix::Checkpoint(&context->lexicon, checkpoint).restore();
        return 0;
      }
    }

    extern "C" std::uint64_t contextPhraseFind(context::Context *context, const std::uint8_t *text,
                                               std::uint64_t offset, std::uint64_t bytes) noexcept {
      if (!validByteSlice(text, offset, bytes)) return 0;
      return findPhrase(context, 0, text, offset * Byte::length, bytes * Byte::length, context_phrase::Exact);
    }

    extern "C" std::uint64_t contextPhraseFindText(context::Context *context, const std::uint8_t *text) noexcept {
      if (text == nullptr) return 0;
      return contextPhraseFind(context, text, 0, std::strlen(reinterpret_cast<const char *>(text)));
    }

    extern "C" std::uint64_t contextPhraseFindBits(context::Context *context, const BitString *text) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return findPhrase(context, 0, data, 0, text->bits, context_phrase::Exact);
    }

    extern "C" std::uint64_t contextPhraseFindBitSlice(context::Context *context, const BitString *text,
                                                       std::uint64_t offset, std::uint64_t bits) noexcept {
      const std::uint8_t *data = nullptr;
      if (!bitView(text, offset, bits, data)) return 0;
      return findPhrase(context, 0, data, offset, bits, context_phrase::Exact);
    }

    extern "C" std::uint64_t contextPhraseFindIn(context::Context *context, std::uint64_t ownerAddress,
                                                 const std::uint8_t *text, std::uint64_t offset, std::uint64_t bytes,
                                                 std::uint64_t mode) noexcept {
      if (!validByteSlice(text, offset, bytes)) return 0;
      return findPhrase(context, ownerAddress, text, offset * Byte::length, bytes * Byte::length, mode);
    }

    extern "C" std::uint64_t contextPhraseFindTextIn(context::Context *context, std::uint64_t ownerAddress,
                                                     const std::uint8_t *text, std::uint64_t mode) noexcept {
      if (text == nullptr) return 0;
      return contextPhraseFindIn(context, ownerAddress, text, 0, std::strlen(reinterpret_cast<const char *>(text)),
                                 mode);
    }

    extern "C" std::uint64_t contextPhraseFindBitsIn(context::Context *context, std::uint64_t ownerAddress,
                                                     const BitString *text, std::uint64_t mode) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return findPhrase(context, ownerAddress, data, 0, text->bits, mode);
    }

    extern "C" std::uint64_t contextPhraseFindBitSliceIn(context::Context *context, std::uint64_t ownerAddress,
                                                         const BitString *text, std::uint64_t offset,
                                                         std::uint64_t bits, std::uint64_t mode) noexcept {
      const std::uint8_t *data = nullptr;
      if (!bitView(text, offset, bits, data)) return 0;
      return findPhrase(context, ownerAddress, data, offset, bits, mode);
    }

    template <context_phrase::Find Mode>
    std::uint64_t contextPhraseFindTextNamed(context::Context *context, std::uint64_t owner,
                                             const std::uint8_t *text) noexcept {
      return contextPhraseFindTextIn(context, owner, text, Mode);
    }

    template <context_phrase::Find Mode>
    std::uint64_t contextPhraseFindNamed(context::Context *context, std::uint64_t owner, const std::uint8_t *text,
                                         std::uint64_t offset, std::uint64_t bytes) noexcept {
      return contextPhraseFindIn(context, owner, text, offset, bytes, Mode);
    }

    template <context_phrase::Find Mode>
    std::uint64_t contextPhraseFindBitsNamed(context::Context *context, std::uint64_t owner,
                                             const BitString *text) noexcept {
      return contextPhraseFindBitsIn(context, owner, text, Mode);
    }

    template <context_phrase::Find Mode>
    std::uint64_t contextPhraseFindBitSliceNamed(context::Context *context, std::uint64_t owner, const BitString *text,
                                                 std::uint64_t offset, std::uint64_t bits) noexcept {
      return contextPhraseFindBitSliceIn(context, owner, text, offset, bits, Mode);
    }

    extern "C" std::uint64_t contextPhraseDefine(context::Context *context, const std::uint8_t *text,
                                                 std::uint64_t offset, std::uint64_t bytes,
                                                 std::uint64_t prototypeAddress) noexcept {
      if (!validByteSlice(text, offset, bytes) || prototypeAddress == 0) return 0;
      return definePhrase(context, 0, text, offset * Byte::length, bytes * Byte::length, 0, prototypeAddress, 0, 0,
                          nullptr, context_phrase::HasPrototype);
    }

    extern "C" std::uint64_t contextPhraseDefineText(context::Context *context, const std::uint8_t *text,
                                                     std::uint64_t prototypeAddress) noexcept {
      if (text == nullptr) return 0;
      return contextPhraseDefine(context, text, 0, std::strlen(reinterpret_cast<const char *>(text)), prototypeAddress);
    }

    extern "C" std::uint64_t contextPhraseDefineBits(context::Context *context, const BitString *text,
                                                     std::uint64_t prototypeAddress) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data) || prototypeAddress == 0) return 0;
      return definePhrase(context, 0, data, 0, text->bits, 0, prototypeAddress, 0, 0, nullptr,
                          context_phrase::HasPrototype);
    }

    extern "C" std::uint64_t contextPhraseDefineBitSlice(context::Context *context, const BitString *text,
                                                         std::uint64_t offset, std::uint64_t bits,
                                                         std::uint64_t prototypeAddress) noexcept {
      const std::uint8_t *data = nullptr;
      if (!bitView(text, offset, bits, data) || prototypeAddress == 0) return 0;
      return definePhrase(context, 0, data, offset, bits, 0, prototypeAddress, 0, 0, nullptr,
                          context_phrase::HasPrototype);
    }

    extern "C" std::uint64_t contextPhraseDefineFull(context::Context *context, std::uint64_t ownerAddress,
                                                     const std::uint8_t *text, std::uint64_t offset,
                                                     std::uint64_t bytes, std::uint64_t typeAddress,
                                                     std::uint64_t prototypeAddress, std::uint64_t successorAddress,
                                                     std::uint64_t actionAddress, std::uint64_t flags) noexcept {
      if (!validByteSlice(text, offset, bytes)) return 0;
      return definePhrase(context, ownerAddress, text, offset * Byte::length, bytes * Byte::length, typeAddress,
                          prototypeAddress, successorAddress, actionAddress, nullptr, flags);
    }

    extern "C" std::uint64_t contextPhraseDefineTextFull(context::Context *context, std::uint64_t ownerAddress,
                                                         const std::uint8_t *text, std::uint64_t typeAddress,
                                                         std::uint64_t prototypeAddress, std::uint64_t successorAddress,
                                                         std::uint64_t actionAddress, std::uint64_t flags) noexcept {
      if (text == nullptr) return 0;
      return contextPhraseDefineFull(context, ownerAddress, text, 0, std::strlen(reinterpret_cast<const char *>(text)),
                                     typeAddress, prototypeAddress, successorAddress, actionAddress, flags);
    }

    extern "C" std::uint64_t contextPhraseDefineFullAction(context::Context *context, std::uint64_t ownerAddress,
                                                           const std::uint8_t *text, std::uint64_t offset,
                                                           std::uint64_t bytes, std::uint64_t typeAddress,
                                                           std::uint64_t prototypeAddress,
                                                           std::uint64_t successorAddress, const PhraseAction *action,
                                                           std::uint64_t flags) noexcept {
      if (!validByteSlice(text, offset, bytes)) return 0;
      return definePhrase(context, ownerAddress, text, offset * Byte::length, bytes * Byte::length, typeAddress,
                          prototypeAddress, successorAddress, 0, action, flags);
    }

    extern "C" std::uint64_t contextPhraseDefineTextFullAction(context::Context *context, std::uint64_t ownerAddress,
                                                               const std::uint8_t *text, std::uint64_t typeAddress,
                                                               std::uint64_t prototypeAddress,
                                                               std::uint64_t successorAddress,
                                                               const PhraseAction *action,
                                                               std::uint64_t flags) noexcept {
      if (text == nullptr) return 0;
      return contextPhraseDefineFullAction(context, ownerAddress, text, 0,
                                           std::strlen(reinterpret_cast<const char *>(text)), typeAddress,
                                           prototypeAddress, successorAddress, action, flags);
    }

    extern "C" std::uint64_t contextPhraseDefineBitsFull(context::Context *context, std::uint64_t ownerAddress,
                                                         const BitString *text, std::uint64_t typeAddress,
                                                         std::uint64_t prototypeAddress, std::uint64_t successorAddress,
                                                         std::uint64_t actionAddress, std::uint64_t flags) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return definePhrase(context, ownerAddress, data, 0, text->bits, typeAddress, prototypeAddress, successorAddress,
                          actionAddress, nullptr, flags);
    }

    extern "C" std::uint64_t contextPhraseDefineBitsFullAction(context::Context *context, std::uint64_t ownerAddress,
                                                               const BitString *text, std::uint64_t typeAddress,
                                                               std::uint64_t prototypeAddress,
                                                               std::uint64_t successorAddress,
                                                               const PhraseAction *action,
                                                               std::uint64_t flags) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return definePhrase(context, ownerAddress, data, 0, text->bits, typeAddress, prototypeAddress, successorAddress,
                          0, action, flags);
    }

    extern "C" std::uint64_t
        contextPhraseDefineBitSliceFull(context::Context *context, std::uint64_t ownerAddress, const BitString *text,
                                        std::uint64_t offset, std::uint64_t bits, std::uint64_t typeAddress,
                                        std::uint64_t prototypeAddress, std::uint64_t successorAddress,
                                        std::uint64_t actionAddress, std::uint64_t flags) noexcept {
      const std::uint8_t *data = nullptr;
      if (!bitView(text, offset, bits, data)) return 0;
      return definePhrase(context, ownerAddress, data, offset, bits, typeAddress, prototypeAddress, successorAddress,
                          actionAddress, nullptr, flags);
    }

    extern "C" std::uint64_t contextPhraseDefineBitSliceFullAction(
        context::Context *context, std::uint64_t ownerAddress, const BitString *text, std::uint64_t offset,
        std::uint64_t bits, std::uint64_t typeAddress, std::uint64_t prototypeAddress, std::uint64_t successorAddress,
        const PhraseAction *action, std::uint64_t flags) noexcept {
      const std::uint8_t *data = nullptr;
      if (!bitView(text, offset, bits, data)) return 0;
      return definePhrase(context, ownerAddress, data, offset, bits, typeAddress, prototypeAddress, successorAddress, 0,
                          action, flags);
    }

    template <std::uint64_t Flags>
    std::uint64_t contextPhraseDefineTextShape(context::Context *context, std::uint64_t owner,
                                               const std::uint8_t *text) noexcept {
      if (text == nullptr) return 0;
      return definePhrase(context, owner, text, 0, std::strlen(reinterpret_cast<const char *>(text)) * Byte::length, 0,
                          0, 0, 0, nullptr, Flags);
    }

    template <std::uint64_t Flags>
    std::uint64_t contextPhraseDefineBitsShape(context::Context *context, std::uint64_t owner,
                                               const BitString *text) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return definePhrase(context, owner, data, 0, text->bits, 0, 0, 0, 0, nullptr, Flags);
    }

    template <std::uint64_t Flags>
    std::uint64_t contextPhraseDefineRootTextShape(context::Context *context, const std::uint8_t *text) noexcept {
      return contextPhraseDefineTextShape<Flags>(context, 0, text);
    }

    template <std::uint64_t Flags>
    std::uint64_t contextPhraseDefineRootBitsShape(context::Context *context, const BitString *text) noexcept {
      return contextPhraseDefineBitsShape<Flags>(context, 0, text);
    }

    std::uint64_t contextPhraseDefineTextFrom(context::Context *context, std::uint64_t owner, const std::uint8_t *text,
                                              std::uint64_t prototype) noexcept {
      if (text == nullptr) return 0;
      return definePhrase(context, owner, text, 0, std::strlen(reinterpret_cast<const char *>(text)) * Byte::length, 0,
                          prototype, 0, 0, nullptr, context_phrase::Serializable | context_phrase::HasPrototype);
    }

    std::uint64_t contextPhraseDefineBitsFrom(context::Context *context, std::uint64_t owner, const BitString *text,
                                              std::uint64_t prototype) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return definePhrase(context, owner, data, 0, text->bits, 0, prototype, 0, 0, nullptr,
                          context_phrase::Serializable | context_phrase::HasPrototype);
    }

    std::uint64_t contextPhraseDefineRootTextFrom(context::Context *context, const std::uint8_t *text,
                                                  std::uint64_t prototype) noexcept {
      return contextPhraseDefineTextFrom(context, 0, text, prototype);
    }

    std::uint64_t contextPhraseDefineRootBitsFrom(context::Context *context, const BitString *text,
                                                  std::uint64_t prototype) noexcept {
      return contextPhraseDefineBitsFrom(context, 0, text, prototype);
    }

    std::uint64_t contextPhraseDefineTextAlias(context::Context *context, std::uint64_t owner, const std::uint8_t *text,
                                               std::uint64_t prototypeAddress) noexcept {
      if (context == nullptr || text == nullptr || prototypeAddress == 0) return 0;
      try {
        lexicon::Phrase prototype = phraseAt(*context, prototypeAddress);
        if (prototype.isNull()) return 0;
        lexicon::Phrase type(&context->lexicon);
        lexicon::Phrase action(&context->lexicon);
        for (std::size_t depth = 0; !prototype.isNull() && depth < 64; ++depth) {
          if (type.isNull() && prototype.containsType()) type = prototype.getType();
          if (action.isNull() && prototype.containsAction()) action = prototype;
          if (!type.isNull() && !action.isNull()) break;
          if (!prototype.containsPrototype()) break;
          prototype = prototype.getPrototype();
        }
        if (type.isNull() || action.isNull()) return 0;
        return definePhrase(context, owner, text, 0, std::strlen(reinterpret_cast<const char *>(text)) * Byte::length,
                            type.getAddress(), prototypeAddress, 0, action.getAddress(), nullptr,
                            context_phrase::Serializable | context_phrase::HasType | context_phrase::HasPrototype |
                                context_phrase::HasAction);
      } catch (...) {
        return 0;
      }
    }

    std::uint64_t contextPhraseDefineRootTextAlias(context::Context *context, const std::uint8_t *text,
                                                   std::uint64_t prototype) noexcept {
      return contextPhraseDefineTextAlias(context, 0, text, prototype);
    }

    std::uint64_t contextPhraseDefineTextSuccessor(context::Context *context, std::uint64_t owner,
                                                   const std::uint8_t *text, std::uint64_t successor) noexcept {
      if (text == nullptr) return 0;
      return definePhrase(context, owner, text, 0, std::strlen(reinterpret_cast<const char *>(text)) * Byte::length, 0,
                          0, successor, 0, nullptr, context_phrase::Serializable | context_phrase::HasSuccessor);
    }

    std::uint64_t contextPhraseDefineBitsSuccessor(context::Context *context, std::uint64_t owner,
                                                   const BitString *text, std::uint64_t successor) noexcept {
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      return definePhrase(context, owner, data, 0, text->bits, 0, 0, successor, 0, nullptr,
                          context_phrase::Serializable | context_phrase::HasSuccessor);
    }

    std::uint64_t contextPhraseDefineRootTextSuccessor(context::Context *context, const std::uint8_t *text,
                                                       std::uint64_t successor) noexcept {
      return contextPhraseDefineTextSuccessor(context, 0, text, successor);
    }

    std::uint64_t contextPhraseDefineRootBitsSuccessor(context::Context *context, const BitString *text,
                                                       std::uint64_t successor) noexcept {
      return contextPhraseDefineBitsSuccessor(context, 0, text, successor);
    }

    std::uint64_t contextPhraseDefineTextAction(context::Context *context, std::uint64_t owner,
                                                const std::uint8_t *text, const PhraseAction *action) noexcept {
      if (context == nullptr || text == nullptr) return 0;
      lexicon::Phrase root = context->lexicon.phrase();
      lexicon::Phrase callable = lexicon::phrase::type::getCallable(root);
      return definePhrase(context, owner, text, 0, std::strlen(reinterpret_cast<const char *>(text)) * Byte::length,
                          callable.getAddress(), 0, 0, 0, action,
                          context_phrase::Serializable | context_phrase::HasType | context_phrase::HasAction);
    }

    std::uint64_t contextPhraseDefineBitsAction(context::Context *context, std::uint64_t owner, const BitString *text,
                                                const PhraseAction *action) noexcept {
      if (context == nullptr) return 0;
      const std::uint8_t *data = nullptr;
      if (text == nullptr || !bitView(text, 0, text->bits, data)) return 0;
      lexicon::Phrase root = context->lexicon.phrase();
      lexicon::Phrase callable = lexicon::phrase::type::getCallable(root);
      return definePhrase(context, owner, data, 0, text->bits, callable.getAddress(), 0, 0, 0, action,
                          context_phrase::Serializable | context_phrase::HasType | context_phrase::HasAction);
    }

    std::uint64_t contextPhraseDefineRootTextAction(context::Context *context, const std::uint8_t *text,
                                                    const PhraseAction *action) noexcept {
      return contextPhraseDefineTextAction(context, 0, text, action);
    }

    std::uint64_t contextPhraseDefineRootBitsAction(context::Context *context, const BitString *text,
                                                    const PhraseAction *action) noexcept {
      return contextPhraseDefineBitsAction(context, 0, text, action);
    }

    extern "C" std::uint64_t contextPhraseSet(context::Context *context, std::uint64_t address, std::uint64_t field,
                                              std::uint64_t value) noexcept {
      if (context == nullptr) return 0;
      try {
        lexicon::Phrase phrase = phraseAt(*context, address);
        if (phrase.isNull()) return 0;
        if (phrase.isPermanent() && !(field == context_phrase::SetPermanent && value != 0)) return 0;
        const auto optional = [&]() {
          if (value == 0) return lexicon::Phrase(&context->lexicon);
          lexicon::Phrase target = phraseAt(*context, value);
          if (target.isNull()) THROW(, "context phrase mutation references an invalid phrase")
          return target;
        };
        switch (field) {
        case context_phrase::SetType: phrase.setType(optional()); break;
        case context_phrase::SetPrototype: phrase.setPrototype(optional()); break;
        case context_phrase::SetSuccessor: phrase.setSuccessor(optional()); break;
        case context_phrase::SetAction: copyAction(phrase, optional()); break;
        case context_phrase::SetSerializable: phrase.setSerializable(value != 0); break;
        case context_phrase::SetPermanent: phrase.setPermanent(value != 0); break;
        case context_phrase::SetRewritable: phrase.setRewritable(value != 0); break;
        default: return 0;
        }
        phrase.save();
        return address;
      } catch (...) {
        return 0;
      }
    }

    extern "C" std::uint64_t contextPhraseSetAction(context::Context *context, std::uint64_t address,
                                                    std::uint64_t field, const PhraseAction *action) noexcept {
      if (context == nullptr || field != context_phrase::SetAction) return 0;
      try {
        lexicon::Phrase phrase = phraseAt(*context, address);
        if (phrase.isNull() || !phrase.containsAction()) return 0;
        Functions::bindAction(phrase, inlineAction(*context, action));
        return address;
      } catch (...) {
        return 0;
      }
    }

    extern "C" std::uint64_t contextPhraseCall(context::Context *context, std::uint64_t address,
                                               std::uint64_t mode) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase phrase = phraseAt(value, address);
        if (phrase.isNull()) return std::uint64_t{0};
        if (mode == context_phrase::Invoke)
          phrase.invoke(value);
        else if (mode == context_phrase::Elaborate)
          phrase.elaborate(value);
        else if (mode == context_phrase::Action)
          lexicon::phrase::type::action(value, phrase);
        else
          return std::uint64_t{0};
        return address;
      });
    }

    extern "C" std::uint64_t contextPhraseGet(context::Context *context, std::uint64_t address,
                                              std::uint64_t field) noexcept {
      if (context == nullptr) return 0;
      try {
        lexicon::Phrase phrase = phraseAt(*context, address);
        if (phrase.isNull()) return 0;
        switch (field) {
        case context_phrase::Parent: return phrase.getParent().getAddress();
        case context_phrase::Type: return phrase.getType().getAddress();
        case context_phrase::Prototype: return phrase.getPrototype().getAddress();
        case context_phrase::Successor: return phrase.getSuccessor().getAddress();
        case context_phrase::PayloadBytes: return phrase.payloadSize();
        case context_phrase::Flags:
          return (phrase.containsSubdictionary() ? context_phrase::Dictionary : 0) |
                 (phrase.isSerializable() ? context_phrase::Serializable : context_phrase::Unserializable) |
                 (phrase.containsType() ? context_phrase::HasType : 0) |
                 (phrase.containsPrototype() ? context_phrase::HasPrototype : 0) |
                 (phrase.containsSuccessor() ? context_phrase::HasSuccessor : 0) |
                 (phrase.containsAction() ? context_phrase::HasAction : 0) |
                 (phrase.isPermanent() ? context_phrase::Permanent : 0) |
                 (phrase.isRewritable() ? context_phrase::Rewritable : 0);
        default: return 0;
        }
      } catch (...) {
        return 0;
      }
    }

    template <context_phrase::Call Mode>
    std::uint64_t contextPhraseCallNamed(context::Context *context, std::uint64_t address) noexcept {
      return contextPhraseCall(context, address, Mode);
    }

    template <context_phrase::Get Field>
    std::uint64_t contextPhraseGetNamed(context::Context *context, std::uint64_t address) noexcept {
      return contextPhraseGet(context, address, Field);
    }

    template <context_phrase::Set Field>
    std::uint64_t contextPhraseSetNamed(context::Context *context, std::uint64_t address,
                                        std::uint64_t value) noexcept {
      return contextPhraseSet(context, address, Field, value);
    }

    std::uint64_t contextPhraseSetActionNamed(context::Context *context, std::uint64_t address,
                                              const PhraseAction *action) noexcept {
      return contextPhraseSetAction(context, address, context_phrase::SetAction, action);
    }

    template <bool Serializable>
    std::uint64_t contextPhraseSetSerializableNamed(context::Context *context, std::uint64_t address) noexcept {
      return contextPhraseSet(context, address, context_phrase::SetSerializable, Serializable ? 1 : 0);
    }

    extern "C" std::uint64_t contextPhraseData(context::Context *context, std::uint64_t address,
                                               const std::uint8_t *data, std::uint64_t offset,
                                               std::uint64_t bytes) noexcept {
      if (context == nullptr || !validByteSlice(data, offset, bytes)) return 0;
      try {
        lexicon::Phrase phrase = phraseAt(*context, address);
        if (phrase.isNull()) return 0;
        Byte output = phrase.allocate(bytes);
        if (bytes != 0) Byte::copy(Byte(const_cast<std::uint8_t *>(data)) + offset, output, bytes);
        phrase.save();
        return address;
      } catch (...) {
        return 0;
      }
    }

    extern "C" std::uint64_t contextPhraseDataText(context::Context *context, std::uint64_t address,
                                                   const std::uint8_t *data) noexcept {
      if (data == nullptr) return 0;
      return contextPhraseData(context, address, data, 0, std::strlen(reinterpret_cast<const char *>(data)));
    }

    extern "C" std::uint64_t contextPhraseKey(context::Context *context, std::uint64_t address,
                                              std::uint8_t *destination, std::uint64_t capacity) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase phrase = phraseAt(value, address);
        if (phrase.isNull()) THROW(, "context phrase key references an invalid phrase")
        const std::string key = phrase.getKey();
        if (destination != nullptr && capacity != 0) {
          const std::size_t copied = std::min<std::uint64_t>(capacity, key.size());
          std::memcpy(destination, key.data(), copied);
        }
        return static_cast<std::uint64_t>(key.size());
      });
    }

    extern "C" std::uint64_t contextPhraseRead(context::Context *context, std::uint64_t address, std::uint64_t offset,
                                               std::uint8_t *destination, std::uint64_t bytes) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase phrase = phraseAt(value, address);
        if (phrase.isNull()) THROW(, "context phrase payload read references an invalid phrase")
        const std::uint64_t available = phrase.payloadSize();
        if (offset > available || bytes > available - offset) THROW(, "context phrase payload read is out of bounds")
        if (bytes != 0 && destination == nullptr) THROW(, "context phrase payload read received a null destination")
        if (bytes != 0) std::memcpy(destination, phrase.content(offset, bytes).toPtr(), bytes);
        return bytes;
      });
    }

    extern "C" std::uint64_t contextPhraseChild(context::Context *context, std::uint64_t ownerAddress,
                                                std::uint64_t afterAddress) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase owner = ownerAt(value, ownerAddress);
        if (owner.isNull() || !owner.containsSubdictionary())
          THROW(, "context phrase child requires a dictionary owner")
        auto filter = [](radix::Node *, radix::Node *candidate) { return !candidate->isEmpty(); };
        lexicon::Dictionary cursor;
        if (afterAddress == 0) {
          cursor = owner.fore(filter);
        } else {
          lexicon::Phrase after = phraseAt(value, afterAddress);
          if (after.isNull() || after.getParent().getAddress() != owner.getAddress())
            THROW(, "context phrase child cursor does not belong to the dictionary owner")
          cursor = lexicon::Dictionary(after.getNode()).next(filter);
        }
        if (cursor.isNull()) return std::uint64_t{0};
        lexicon::Phrase child = cursor.getPhrase();
        return child.isNull() ? std::uint64_t{0} : static_cast<std::uint64_t>(child.getAddress());
      });
    }

    std::uint64_t contextPhraseFirstChild(context::Context *context, std::uint64_t owner) noexcept {
      return contextPhraseChild(context, owner, 0);
    }

    extern "C" std::uint64_t contextSourceEnsure(context::Context *context, std::uint64_t bytes) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) { return sourceAvailable(value, bytes); });
    }

    extern "C" const std::uint8_t *contextSourceData(context::Context *context) noexcept {
      return checked(context, static_cast<const std::uint8_t *>(nullptr), [&](context::Context &value) {
        if (sourceAvailable(value, 1) == 0) return static_cast<const std::uint8_t *>(nullptr);
        const std::size_t offset = value.source.buffer.offset / Byte::length;
        return reinterpret_cast<const std::uint8_t *>(value.source.buffer.str.data() + offset);
      });
    }

    extern "C" std::uint64_t contextSourceBytes(context::Context *context) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        return static_cast<std::uint64_t>(value.source.buffer.bits / Byte::length);
      });
    }

    extern "C" std::uint64_t contextSourcePeek(context::Context *context, std::uint64_t relative) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (relative == std::numeric_limits<std::uint64_t>::max() || sourceAvailable(value, relative + 1) <= relative)
          return std::uint64_t{0};
        const std::size_t offset = value.source.buffer.offset / Byte::length + relative;
        return static_cast<std::uint64_t>(static_cast<std::uint8_t>(value.source.buffer.str[offset]));
      });
    }

    extern "C" std::uint64_t contextSourceAdvance(context::Context *context, std::uint64_t bytes) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (sourceAvailable(value, bytes) < bytes) THROW(, "context source advance exceeds available input")
        context::Source::progress(value, bytes * Byte::length);
        return bytes;
      });
    }

    extern "C" std::uint64_t contextSourceRoot(context::Context *context) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase root = value.lexicon.phrase();
        value.lookup.stack.clear();
        context::Lookup::in(value, root);
        return static_cast<std::uint64_t>(root.getAddress());
      });
    }

    extern "C" std::uint64_t contextSourceMatch(context::Context *context, std::uint64_t ownerAddress,
                                                std::uint64_t mode) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase owner = ownerAt(value, ownerAddress);
        if (owner.isNull() || !owner.containsSubdictionary())
          THROW(, "context source match requires a dictionary owner")
        lexicon::Dictionary dictionary = owner.getSubdictionary();
        auto filter = [](lexicon::Dictionary *, lexicon::Match *candidate) { return !candidate->getPhrase().isNull(); };
        lexicon::Phrase matched(&value.lexicon);
        if (mode == context_phrase::First)
          matched = context::Source::matchFirst(value, dictionary, filter, true);
        else if (mode == context_phrase::Longest)
          matched = context::Source::matchLongest(value, dictionary, filter, true);
        else if (mode == context_phrase::Exact)
          matched = context::Source::matchExact(value, dictionary, filter, true);
        else
          THROW(, "context source match received an invalid mode")
        return matched.isNull() ? std::uint64_t{0} : static_cast<std::uint64_t>(matched.getAddress());
      });
    }

    template <context_phrase::Find Mode>
    std::uint64_t contextSourceMatchNamed(context::Context *context, std::uint64_t owner) noexcept {
      return contextSourceMatch(context, owner, Mode);
    }

    extern "C" std::uint64_t contextSyntaxDictionary(context::Context *context) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        lexicon::Phrase dictionary = SyntaxExtension::dictionary(value);
        if (dictionary.isNull()) THROW(, "fn syntax rewrite dictionary is unavailable")
        return static_cast<std::uint64_t>(dictionary.getAddress());
      });
    }

    extern "C" std::uint64_t contextSyntaxActive(context::Context *context) noexcept {
      return context != nullptr && SyntaxExtension::active(*context);
    }

    extern "C" const std::uint8_t *contextSyntaxData(context::Context *context) noexcept {
      return checked(context, static_cast<const std::uint8_t *>(nullptr),
                     [&](context::Context &value) { return SyntaxExtension::data(value); });
    }

    extern "C" std::uint64_t contextSyntaxBytes(context::Context *context) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) { return SyntaxExtension::bytes(value); });
    }

    extern "C" std::uint64_t contextSyntaxAdvance(context::Context *context, std::uint64_t bytes) noexcept {
      return checked(context, std::uint64_t{0},
                     [&](context::Context &value) { return SyntaxExtension::advance(value, bytes); });
    }

    extern "C" std::uint64_t contextSyntaxEmit(context::Context *context, const std::uint8_t *source,
                                               std::uint64_t offset, std::uint64_t bytes) noexcept {
      return checked(context, std::uint64_t{0},
                     [&](context::Context &value) { return SyntaxExtension::emit(value, source, offset, bytes); });
    }

    extern "C" std::uint64_t contextSyntaxEmitText(context::Context *context, const std::uint8_t *source) noexcept {
      if (source == nullptr) return 0;
      return contextSyntaxEmit(context, source, 0, std::strlen(reinterpret_cast<const char *>(source)));
    }

    extern "C" std::uint64_t contextSyntaxCopy(context::Context *context, std::uint64_t bytes) noexcept {
      return checked(context, std::uint64_t{0},
                     [&](context::Context &value) { return SyntaxExtension::copy(value, bytes); });
    }

    extern "C" std::uint64_t contextSyntaxMatch(context::Context *context, std::uint64_t owner,
                                                std::uint64_t mode) noexcept {
      return checked(context, std::uint64_t{0},
                     [&](context::Context &value) { return SyntaxExtension::match(value, owner, mode); });
    }

    extern "C" std::uint64_t contextSyntaxElaborate(context::Context *context, std::uint64_t owner) noexcept {
      return checked(context, std::uint64_t{0},
                     [&](context::Context &value) { return SyntaxExtension::elaborate(value, owner); });
    }

    template <context_phrase::Find Mode>
    std::uint64_t contextSyntaxMatchNamed(context::Context *context, std::uint64_t owner) noexcept {
      return contextSyntaxMatch(context, owner, Mode);
    }

    extern "C" const std::uint8_t *contextSyntaxPath(context::Context *context) noexcept {
      return checked(context, static_cast<const std::uint8_t *>(nullptr),
                     [&](context::Context &value) { return SyntaxExtension::path(value); });
    }

    extern "C" std::uint64_t contextSyntaxLine(context::Context *context) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) { return SyntaxExtension::line(value); });
    }

    extern "C" std::uint64_t contextSyntaxPosition(context::Context *context) noexcept {
      return checked(context, std::uint64_t{0},
                     [&](context::Context &value) { return SyntaxExtension::position(value); });
    }

    extern "C" SourceBlock *contextSourceBlockCapture(context::Context *context) noexcept {
      return checked(context, static_cast<SourceBlock *>(nullptr),
                     [&](context::Context &value) { return new SourceBlock(Blocks::capture(value)); });
    }

    extern "C" const std::uint8_t *contextSourceBlockHeader(SourceBlock *block) noexcept {
      return block == nullptr ? nullptr : reinterpret_cast<const std::uint8_t *>(block->header.c_str());
    }

    extern "C" const std::uint8_t *contextSourceBlockBody(SourceBlock *block) noexcept {
      return block == nullptr ? nullptr : reinterpret_cast<const std::uint8_t *>(block->body.c_str());
    }

    extern "C" const std::uint8_t *contextSourceBlockPath(SourceBlock *block) noexcept {
      return block == nullptr ? nullptr : reinterpret_cast<const std::uint8_t *>(block->path.c_str());
    }

    extern "C" std::uint64_t contextSourceBlockHeaderLine(SourceBlock *block) noexcept {
      return block == nullptr ? 0 : block->headerLine;
    }

    extern "C" std::uint64_t contextSourceBlockHeaderPosition(SourceBlock *block) noexcept {
      return block == nullptr ? 0 : block->headerPosition;
    }

    extern "C" std::uint64_t contextSourceBlockLine(SourceBlock *block) noexcept {
      return block == nullptr ? 0 : block->line;
    }

    extern "C" std::uint64_t contextSourceBlockPosition(SourceBlock *block) noexcept {
      return block == nullptr ? 0 : block->position;
    }

    extern "C" std::uint64_t contextSourceBlockExecute(context::Context *context, SourceBlock *block,
                                                       std::uint64_t scoped) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (block == nullptr) THROW(, "context source block execute received a null block")
        Blocks::execute(value, *block, scoped != 0);
        return std::uint64_t{1};
      });
    }

    template <bool Scoped>
    std::uint64_t contextSourceBlockExecuteNamed(context::Context *context, SourceBlock *block) noexcept {
      return contextSourceBlockExecute(context, block, Scoped ? 1 : 0);
    }

    extern "C" void contextSourceBlockRelease(SourceBlock *block) noexcept {
      delete block;
    }

    extern "C" std::uint64_t contextDiagnosticError(context::Context *context, const std::uint8_t *message) noexcept {
      if (context == nullptr || context->exec.pendingException) return 0;
      try {
        if (message == nullptr) THROW(, "context diagnostic received a null message")
        const SourceLocation location{context->source.path, context->source.line, context->source.position};
        THROW_AT(location, reinterpret_cast<const char *>(message))
      } catch (...) {
        context->exec.pendingException = std::current_exception();
      }
      return 0;
    }

    extern "C" std::uint64_t contextDiagnosticErrorAt(context::Context *context, const std::uint8_t *path,
                                                      std::uint64_t line, std::uint64_t column,
                                                      const std::uint8_t *message) noexcept {
      if (context == nullptr || context->exec.pendingException) return 0;
      try {
        if (message == nullptr) THROW(, "context diagnostic received a null message")
        const SourceLocation location{path == nullptr ? context->source.path : reinterpret_cast<const char *>(path),
                                      line, column};
        THROW_AT(location, reinterpret_cast<const char *>(message))
      } catch (...) {
        context->exec.pendingException = std::current_exception();
      }
      return 0;
    }

    extern "C" std::uint8_t *contextExpressionFormatAt(context::Context *context, const std::uint8_t *source,
                                                       std::uint64_t offset, std::uint64_t bytes,
                                                       const std::uint8_t *path, std::uint64_t line,
                                                       std::uint64_t column) noexcept {
      if (source == nullptr || !validByteSlice(source, offset, bytes)) return nullptr;
      return checked(context, static_cast<std::uint8_t *>(nullptr), [&](context::Context &value) {
        const std::string_view complete(reinterpret_cast<const char *>(source), offset + bytes);
        SourceLocation origin{path == nullptr ? value.source.path : reinterpret_cast<const char *>(path), line, column};
        origin = sourceLocationAt(std::move(origin), complete, offset);
        return ownedText(Expressions::evaluate(value, complete.substr(offset, bytes), std::move(origin)).format());
      });
    }

    extern "C" std::uint8_t *contextExpressionFormat(context::Context *context, const std::uint8_t *source,
                                                     std::uint64_t offset, std::uint64_t bytes) noexcept {
      if (context == nullptr) return nullptr;
      return contextExpressionFormatAt(context, source, offset, bytes,
                                       reinterpret_cast<const std::uint8_t *>(context->source.path.c_str()),
                                       context->source.line, context->source.position);
    }

    extern "C" std::uint8_t *contextExpressionFormatText(context::Context *context,
                                                         const std::uint8_t *source) noexcept {
      if (source == nullptr) return nullptr;
      return contextExpressionFormat(context, source, 0, std::strlen(reinterpret_cast<const char *>(source)));
    }

    extern "C" std::uint64_t contextValueContains(context::Context *context, const std::uint8_t *name) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context value lookup received a null name")
        return static_cast<std::uint64_t>(value.values().contains(reinterpret_cast<const char *>(name)));
      });
    }

    extern "C" std::uint8_t *contextValueFormat(context::Context *context, const std::uint8_t *name) noexcept {
      return checked(context, static_cast<std::uint8_t *>(nullptr), [&](context::Context &value) {
        if (name == nullptr) THROW(, "context value lookup received a null name")
        return ownedText(value.values().get(reinterpret_cast<const char *>(name)).format());
      });
    }

    extern "C" std::uint64_t contextValueDefineText(context::Context *context, const std::uint8_t *name,
                                                    const std::uint8_t *text) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr || text == nullptr) THROW(, "context value definition received null text")
        const std::string variable(reinterpret_cast<const char *>(name));
        value.values().define(variable, reinterpret_cast<const char *>(text), true);
        Expressions::bindAssignment(value, variable);
        return std::uint64_t{1};
      });
    }

    extern "C" std::uint64_t contextValueDefineInteger(context::Context *context, const std::uint8_t *name,
                                                       std::int64_t integer) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context integer definition received a null name")
        const std::string variable(reinterpret_cast<const char *>(name));
        value.values().define(variable, context::Value(integer), true);
        Expressions::bindAssignment(value, variable);
        return std::uint64_t{1};
      });
    }

    extern "C" std::uint64_t contextValueAssignText(context::Context *context, const std::uint8_t *name,
                                                    const std::uint8_t *text) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr || text == nullptr) THROW(, "context value assignment received null text")
        value.values().assign(reinterpret_cast<const char *>(name), reinterpret_cast<const char *>(text));
        return std::uint64_t{1};
      });
    }

    extern "C" std::uint64_t contextValueAssignInteger(context::Context *context, const std::uint8_t *name,
                                                       std::int64_t integer) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context integer assignment received a null name")
        value.values().assign(reinterpret_cast<const char *>(name), context::Value(integer));
        return std::uint64_t{1};
      });
    }

    extern "C" std::uint64_t contextTypeFind(context::Context *context, const std::uint8_t *name) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context type find received a null name")
        return static_cast<std::uint64_t>(value.language().types.find(reinterpret_cast<const char *>(name)));
      });
    }

    extern "C" std::uint64_t contextTypeGet(context::Context *context, std::uint64_t type,
                                            std::uint64_t field) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        const compiler::TypeDescriptor descriptor = value.language().types.get(static_cast<compiler::TypeId>(type));
        switch (field) {
        case context_type::Kind: return static_cast<std::uint64_t>(descriptor.kind);
        case context_type::Size: return static_cast<std::uint64_t>(descriptor.size);
        case context_type::Alignment: return static_cast<std::uint64_t>(descriptor.alignment);
        case context_type::Signed: return static_cast<std::uint64_t>(descriptor.isSigned);
        case context_type::Element: return static_cast<std::uint64_t>(descriptor.element);
        case context_type::ElementCount: return static_cast<std::uint64_t>(descriptor.elementCount);
        case context_type::PointerDepth: return static_cast<std::uint64_t>(descriptor.pointerDepth);
        case context_type::Result: return static_cast<std::uint64_t>(descriptor.resultType);
        default: THROW(, "context type get received an invalid field")
        }
      });
    }

    template <context_type::Get Field>
    std::uint64_t contextTypeGetNamed(context::Context *context, std::uint64_t type) noexcept {
      return contextTypeGet(context, type, Field);
    }

    extern "C" std::uint64_t contextTypeInteger(context::Context *context, const std::uint8_t *name, std::uint64_t bits,
                                                std::uint64_t isSigned) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context integer type received a null name")
        return static_cast<std::uint64_t>(
            value.language().types.defineInteger(reinterpret_cast<const char *>(name), bits, isSigned != 0));
      });
    }

    template <bool Signed>
    std::uint64_t contextTypeIntegerNamed(context::Context *context, const std::uint8_t *name,
                                          std::uint64_t bits) noexcept {
      return contextTypeInteger(context, name, bits, Signed ? 1 : 0);
    }

    extern "C" std::uint64_t contextTypeFloating(context::Context *context, const std::uint8_t *name,
                                                 std::uint64_t bits) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context floating type received a null name")
        return static_cast<std::uint64_t>(
            value.language().types.defineFloatingPoint(reinterpret_cast<const char *>(name), bits));
      });
    }

    extern "C" std::uint64_t contextTypePointer(context::Context *context, std::uint64_t element) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        return static_cast<std::uint64_t>(value.language().types.pointerTo(static_cast<compiler::TypeId>(element)));
      });
    }

    extern "C" std::uint64_t contextTypeArray(context::Context *context, std::uint64_t element,
                                              std::uint64_t count) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        return static_cast<std::uint64_t>(
            value.language().types.arrayOf(static_cast<compiler::TypeId>(element), count));
      });
    }

    std::vector<compiler::TypeId> phraseTypeList(context::Context &context, std::uint64_t firstAddress,
                                                 std::vector<compiler::FieldDeclaration> *fields = nullptr) {
      std::vector<compiler::TypeId> result;
      std::unordered_set<Size> visited;
      lexicon::Phrase current = phraseAt(context, firstAddress);
      if (current.isNull()) THROW(, "context type phrase list starts with an invalid phrase")
      while (!current.isNull()) {
        if (!visited.insert(current.getAddress()).second) THROW(, "context type phrase list contains a cycle")
        if (current.payloadSize() < sizeof(std::uint64_t))
          THROW(, "context type phrase list item requires a u64 type payload")
        std::uint64_t raw = 0;
        current.fetch(0, raw);
        if (raw > std::numeric_limits<compiler::TypeId>::max())
          THROW(, "context type phrase list item contains an invalid type id")
        const compiler::TypeId type = static_cast<compiler::TypeId>(raw);
        context.language().types.get(type);
        result.push_back(type);
        if (fields != nullptr) {
          const std::string name = current.getKey();
          if (name.empty()) THROW(, "context structure field name cannot be empty")
          fields->push_back({name, type});
        }
        if (!current.containsSuccessor()) break;
        current = current.getSuccessor();
      }
      return result;
    }

    extern "C" std::uint64_t contextTypeDeclareStructure(context::Context *context, const std::uint8_t *name) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (name == nullptr) THROW(, "context structure type received a null name")
        return static_cast<std::uint64_t>(
            value.language().types.declareStructure(reinterpret_cast<const char *>(name)));
      });
    }

    extern "C" std::uint64_t contextTypeCompleteStructure(context::Context *context, std::uint64_t structure,
                                                          std::uint64_t firstField, std::uint64_t packed,
                                                          std::uint64_t alignment) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        std::vector<compiler::FieldDeclaration> fields;
        if (firstField != 0) (void)phraseTypeList(value, firstField, &fields);
        const compiler::TypeId type = static_cast<compiler::TypeId>(structure);
        value.language().types.completeStructure(type, fields, packed != 0, alignment);
        return static_cast<std::uint64_t>(type);
      });
    }

    template <bool Packed>
    std::uint64_t contextTypeCompleteStructureNatural(context::Context *context, std::uint64_t structure,
                                                      std::uint64_t firstField) noexcept {
      return contextTypeCompleteStructure(context, structure, firstField, Packed ? 1 : 0, 0);
    }

    std::uint64_t contextTypeCompleteStructureAligned(context::Context *context, std::uint64_t structure,
                                                      std::uint64_t firstField, std::uint64_t alignment) noexcept {
      return contextTypeCompleteStructure(context, structure, firstField, 0, alignment);
    }

    extern "C" std::uint64_t contextTypeFunction(context::Context *context, std::uint64_t firstParameter,
                                                 std::uint64_t result, const std::uint8_t *convention,
                                                 std::uint64_t variadic) noexcept {
      return checked(context, std::uint64_t{0}, [&](context::Context &value) {
        if (convention == nullptr) THROW(, "context function type received a null ABI convention")
        const std::vector<compiler::TypeId> parameters =
            firstParameter == 0 ? std::vector<compiler::TypeId>{} : phraseTypeList(value, firstParameter);
        return static_cast<std::uint64_t>(
            value.language().types.functionOf(parameters, static_cast<compiler::TypeId>(result),
                                              reinterpret_cast<const char *>(convention), variadic != 0));
      });
    }

    template <bool Variadic>
    std::uint64_t contextTypeFunctionNamed(context::Context *context, std::uint64_t firstParameter,
                                           std::uint64_t result, const std::uint8_t *convention) noexcept {
      return contextTypeFunction(context, firstParameter, result, convention, Variadic ? 1 : 0);
    }

    void declareHostFunction(context::Context &context, std::string_view name, std::string_view symbol,
                             std::initializer_list<compiler::TypeId> parameters, compiler::TypeId result,
                             std::uintptr_t address) {
      compiler::LanguageState language = context.language();
      compiler::TypedFunction function;
      function.name = std::string(name);
      function.signature.symbol = std::string(symbol);
      function.signature.convention = language.convention("sysv-amd64");
      function.parameterTypes.assign(parameters.begin(), parameters.end());
      for (compiler::TypeId parameter : function.parameterTypes)
        function.signature.parameters.push_back(language.types.abiType(parameter));
      function.resultType = result;
      function.signature.result = language.types.abiType(result);
      function.imported = true;

      const std::size_t separator = function.name.rfind(':');
      if (separator != std::string::npos && !function.parameterTypes.empty()) {
        compiler::TypeDescriptor receiver = language.types.get(function.parameterTypes.front());
        if (receiver.kind == compiler::TypeKind::Pointer) receiver = language.types.get(receiver.element);
        if (receiver.kind == compiler::TypeKind::Structure && receiver.name == function.name.substr(0, separator))
          language.types.addMethod(receiver.id, function.name.substr(separator + 1), function.signature);
      }
      language.declareFunction(std::move(function));
      compiler::DynamicLinker::instance().registerSymbol(std::string(symbol), address);
    }
  } // namespace

  void ContextApi::setup(context::Context &context) {
    compiler::LanguageState language = context.language();
    const compiler::TypeId contextPointer = language.types.find("Context*");
    const compiler::TypeId bytePointer = language.types.find("u8*");
    const compiler::TypeId bitStringPointer = language.types.find("BitString*");
    const compiler::TypeId phraseActionPointer = language.types.find("PhraseAction*");
    const compiler::TypeId sourceBlockPointer = language.types.find("SourceBlock*");
    const compiler::TypeId i64 = language.types.find("i64");
    const compiler::TypeId u64 = language.types.find("u64");
    const compiler::TypeId voidType = language.types.find("void");
    declareHostFunction(context, FindPhrase, "context:phrase:find$root-text", {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindText));
    declareHostFunction(context, FindPhrase, "context:phrase:find$root", {contextPointer, bytePointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFind));
    declareHostFunction(context, FindPhrase, "context:phrase:find$root-bits", {contextPointer, bitStringPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindBits));
    declareHostFunction(context, FindPhrase, "context:phrase:find$root-bit-slice",
                        {contextPointer, bitStringPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindBitSlice));
    declareHostFunction(context, FindPhrase, "context:phrase:find$in-text", {contextPointer, u64, bytePointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextPhraseFindTextIn));
    declareHostFunction(context, FindPhrase, "context:phrase:find$in",
                        {contextPointer, u64, bytePointer, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindIn));
    declareHostFunction(context, FindPhrase, "context:phrase:find$in-bits",
                        {contextPointer, u64, bitStringPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindBitsIn));
    declareHostFunction(context, FindPhrase, "context:phrase:find$in-bit-slice",
                        {contextPointer, u64, bitStringPointer, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindBitSliceIn));
    const auto declareNamedFind = [&](std::string_view name, context_phrase::Find mode) {
      const auto text = mode == context_phrase::Exact   ? &contextPhraseFindTextNamed<context_phrase::Exact>
                        : mode == context_phrase::First ? &contextPhraseFindTextNamed<context_phrase::First>
                                                        : &contextPhraseFindTextNamed<context_phrase::Longest>;
      const auto slice = mode == context_phrase::Exact   ? &contextPhraseFindNamed<context_phrase::Exact>
                         : mode == context_phrase::First ? &contextPhraseFindNamed<context_phrase::First>
                                                         : &contextPhraseFindNamed<context_phrase::Longest>;
      const auto bits = mode == context_phrase::Exact   ? &contextPhraseFindBitsNamed<context_phrase::Exact>
                        : mode == context_phrase::First ? &contextPhraseFindBitsNamed<context_phrase::First>
                                                        : &contextPhraseFindBitsNamed<context_phrase::Longest>;
      const auto bitSlice = mode == context_phrase::Exact   ? &contextPhraseFindBitSliceNamed<context_phrase::Exact>
                            : mode == context_phrase::First ? &contextPhraseFindBitSliceNamed<context_phrase::First>
                                                            : &contextPhraseFindBitSliceNamed<context_phrase::Longest>;
      const std::string symbol(name);
      declareHostFunction(context, name, symbol + "$text", {contextPointer, u64, bytePointer}, u64,
                          reinterpret_cast<std::uintptr_t>(text));
      declareHostFunction(context, name, symbol + "$slice", {contextPointer, u64, bytePointer, u64, u64}, u64,
                          reinterpret_cast<std::uintptr_t>(slice));
      declareHostFunction(context, name, symbol + "$bits", {contextPointer, u64, bitStringPointer}, u64,
                          reinterpret_cast<std::uintptr_t>(bits));
      declareHostFunction(context, name, symbol + "$bit-slice", {contextPointer, u64, bitStringPointer, u64, u64}, u64,
                          reinterpret_cast<std::uintptr_t>(bitSlice));
    };
    declareNamedFind("context:phrase:find:exact", context_phrase::Exact);
    declareNamedFind("context:phrase:find:first", context_phrase::First);
    declareNamedFind("context:phrase:find:longest", context_phrase::Longest);
    declareHostFunction(context, "Context:phrase_find_exact", "Context:phrase_find_exact",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindTextNamed<context_phrase::Exact>));
    declareHostFunction(context, "Context:phrase_find_first", "Context:phrase_find_first",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindTextNamed<context_phrase::First>));
    declareHostFunction(context, "Context:phrase_find_longest", "Context:phrase_find_longest",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFindTextNamed<context_phrase::Longest>));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$prototype-text",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineText));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$prototype",
                        {contextPointer, bytePointer, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefine));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$prototype-bits",
                        {contextPointer, bitStringPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBits));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$prototype-bit-slice",
                        {contextPointer, bitStringPointer, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitSlice));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-text",
                        {contextPointer, u64, bytePointer, u64, u64, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextFull));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-text-action",
                        {contextPointer, u64, bytePointer, u64, u64, u64, phraseActionPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextFullAction));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full",
                        {contextPointer, u64, bytePointer, u64, u64, u64, u64, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineFull));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-action",
                        {contextPointer, u64, bytePointer, u64, u64, u64, u64, u64, phraseActionPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineFullAction));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-bits",
                        {contextPointer, u64, bitStringPointer, u64, u64, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsFull));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-bits-action",
                        {contextPointer, u64, bitStringPointer, u64, u64, u64, phraseActionPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsFullAction));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-bit-slice",
                        {contextPointer, u64, bitStringPointer, u64, u64, u64, u64, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitSliceFull));
    declareHostFunction(context, DefinePhrase, "context:phrase:define$full-bit-slice-action",
                        {contextPointer, u64, bitStringPointer, u64, u64, u64, u64, u64, phraseActionPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitSliceFullAction));
    constexpr std::uint64_t dataFlags = context_phrase::Serializable;
    constexpr std::uint64_t dictionaryFlags = context_phrase::Dictionary | context_phrase::Serializable;
    declareHostFunction(context, "context:phrase:define:data", "context:phrase:define:data$text",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextShape<dataFlags>));
    declareHostFunction(context, "context:phrase:define:data", "context:phrase:define:data$root-text",
                        {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextShape<dataFlags>));
    declareHostFunction(context, "context:phrase:define:data", "context:phrase:define:data$bits",
                        {contextPointer, u64, bitStringPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsShape<dataFlags>));
    declareHostFunction(context, "context:phrase:define:data", "context:phrase:define:data$root-bits",
                        {contextPointer, bitStringPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootBitsShape<dataFlags>));
    declareHostFunction(context, "context:phrase:define:dictionary", "context:phrase:define:dictionary$text",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextShape<dictionaryFlags>));
    declareHostFunction(context, "context:phrase:define:dictionary", "context:phrase:define:dictionary$root-text",
                        {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextShape<dictionaryFlags>));
    declareHostFunction(context, "context:phrase:define:dictionary", "context:phrase:define:dictionary$bits",
                        {contextPointer, u64, bitStringPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsShape<dictionaryFlags>));
    declareHostFunction(context, "context:phrase:define:dictionary", "context:phrase:define:dictionary$root-bits",
                        {contextPointer, bitStringPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootBitsShape<dictionaryFlags>));
    declareHostFunction(context, "context:phrase:define:from", "context:phrase:define:from$text",
                        {contextPointer, u64, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextFrom));
    declareHostFunction(context, "context:phrase:define:from", "context:phrase:define:from$root-text",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextFrom));
    declareHostFunction(context, "context:phrase:define:from", "context:phrase:define:from$bits",
                        {contextPointer, u64, bitStringPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsFrom));
    declareHostFunction(context, "context:phrase:define:from", "context:phrase:define:from$root-bits",
                        {contextPointer, bitStringPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootBitsFrom));
    declareHostFunction(context, DefinePhraseAlias, "context:phrase:define:alias$text",
                        {contextPointer, u64, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextAlias));
    declareHostFunction(context, DefinePhraseAlias, "context:phrase:define:alias$root-text",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextAlias));
    declareHostFunction(context, "context:phrase:define:successor", "context:phrase:define:successor$text",
                        {contextPointer, u64, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextSuccessor));
    declareHostFunction(context, "context:phrase:define:successor", "context:phrase:define:successor$root-text",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextSuccessor));
    declareHostFunction(context, "context:phrase:define:successor", "context:phrase:define:successor$bits",
                        {contextPointer, u64, bitStringPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsSuccessor));
    declareHostFunction(context, "context:phrase:define:successor", "context:phrase:define:successor$root-bits",
                        {contextPointer, bitStringPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootBitsSuccessor));
    declareHostFunction(context, "context:phrase:define:action", "context:phrase:define:action$text",
                        {contextPointer, u64, bytePointer, phraseActionPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextAction));
    declareHostFunction(context, "context:phrase:define:action", "context:phrase:define:action$root-text",
                        {contextPointer, bytePointer, phraseActionPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextAction));
    declareHostFunction(context, "context:phrase:define:action", "context:phrase:define:action$bits",
                        {contextPointer, u64, bitStringPointer, phraseActionPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineBitsAction));
    declareHostFunction(context, "context:phrase:define:action", "context:phrase:define:action$root-bits",
                        {contextPointer, bitStringPointer, phraseActionPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootBitsAction));
    declareHostFunction(context, "Context:phrase_define_data", "Context:phrase_define_data",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextShape<dataFlags>));
    declareHostFunction(context, "Context:phrase_define_data", "Context:phrase_define_data$root",
                        {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextShape<dataFlags>));
    declareHostFunction(context, "Context:phrase_define_dictionary", "Context:phrase_define_dictionary",
                        {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextShape<dictionaryFlags>));
    declareHostFunction(context, "Context:phrase_define_dictionary", "Context:phrase_define_dictionary$root",
                        {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextShape<dictionaryFlags>));
    declareHostFunction(context, "Context:phrase_define_from", "Context:phrase_define_from",
                        {contextPointer, u64, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineTextFrom));
    declareHostFunction(context, "Context:phrase_define_from", "Context:phrase_define_from$root",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDefineRootTextFrom));
    declareHostFunction(context, CallPhrase, "context:phrase:call", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseCall));
    declareHostFunction(context, GetPhrase, "context:phrase:get", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseGet));
    declareHostFunction(context, SetPhrase, "context:phrase:set$value", {contextPointer, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSet));
    declareHostFunction(context, SetPhrase, "context:phrase:set$action",
                        {contextPointer, u64, u64, phraseActionPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetAction));
    declareHostFunction(context, "context:phrase:invoke", "context:phrase:invoke", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseCallNamed<context_phrase::Invoke>));
    declareHostFunction(context, "context:phrase:elaborate", "context:phrase:elaborate", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseCallNamed<context_phrase::Elaborate>));
    declareHostFunction(context, "context:phrase:dispatch", "context:phrase:dispatch", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseCallNamed<context_phrase::Action>));
    declareHostFunction(context, "context:phrase:parent", "context:phrase:parent", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseGetNamed<context_phrase::Parent>));
    declareHostFunction(context, "context:phrase:type", "context:phrase:type", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseGetNamed<context_phrase::Type>));
    declareHostFunction(context, "context:phrase:prototype", "context:phrase:prototype", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseGetNamed<context_phrase::Prototype>));
    declareHostFunction(context, "context:phrase:successor", "context:phrase:successor", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseGetNamed<context_phrase::Successor>));
    declareHostFunction(context, "context:phrase:payload:bytes", "context:phrase:payload:bytes", {contextPointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextPhraseGetNamed<context_phrase::PayloadBytes>));
    declareHostFunction(context, "context:phrase:flags", "context:phrase:flags", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseGetNamed<context_phrase::Flags>));
    declareHostFunction(context, "context:phrase:set:type", "context:phrase:set:type", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetType>));
    declareHostFunction(context, "context:phrase:set:prototype", "context:phrase:set:prototype",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetPrototype>));
    declareHostFunction(context, "context:phrase:set:successor", "context:phrase:set:successor",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetSuccessor>));
    declareHostFunction(context, "context:phrase:set:action", "context:phrase:set:action$value",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetAction>));
    declareHostFunction(context, "context:phrase:set:action", "context:phrase:set:action$inline",
                        {contextPointer, u64, phraseActionPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetActionNamed));
    declareHostFunction(context, "context:phrase:set:serializable", "context:phrase:set:serializable",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetSerializable>));
    declareHostFunction(context, "context:phrase:set:serializable", "context:phrase:set:serializable$enabled",
                        {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetSerializableNamed<true>));
    declareHostFunction(context, "context:phrase:set:transient", "context:phrase:set:transient", {contextPointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextPhraseSetSerializableNamed<false>));
    declareHostFunction(context, "context:phrase:set:permanent", "context:phrase:set:permanent",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetPermanent>));
    declareHostFunction(context, "context:phrase:set:rewrite", "context:phrase:set:rewrite", {contextPointer, u64, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextPhraseSetNamed<context_phrase::SetRewritable>));
    declareHostFunction(context, DataPhrase, "context:phrase:data$text", {contextPointer, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseDataText));
    declareHostFunction(context, DataPhrase, "context:phrase:data", {contextPointer, u64, bytePointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseData));
    declareHostFunction(context, KeyPhrase, "context:phrase:key", {contextPointer, u64, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseKey));
    declareHostFunction(context, ReadPhrase, "context:phrase:read", {contextPointer, u64, u64, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseRead));
    declareHostFunction(context, ChildPhrase, "context:phrase:child", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseChild));
    declareHostFunction(context, "context:phrase:child:first", "context:phrase:child:first", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextPhraseFirstChild));
    declareHostFunction(context, "context:phrase:child:next", "context:phrase:child:next", {contextPointer, u64, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextPhraseChild));

    declareHostFunction(context, SourceEnsure, "context:source:ensure", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceEnsure));
    declareHostFunction(context, SourceData, "context:source:data", {contextPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceData));
    declareHostFunction(context, SourceBytes, "context:source:bytes", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBytes));
    declareHostFunction(context, SourcePeek, "context:source:peek", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourcePeek));
    declareHostFunction(context, SourceAdvance, "context:source:advance", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceAdvance));
    declareHostFunction(context, SourceRoot, "context:source:root", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceRoot));
    declareHostFunction(context, SourceMatch, "context:source:match", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceMatch));
    declareHostFunction(context, "context:source:match:exact", "context:source:match:exact", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceMatchNamed<context_phrase::Exact>));
    declareHostFunction(context, "context:source:match:first", "context:source:match:first", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceMatchNamed<context_phrase::First>));
    declareHostFunction(context, "context:source:match:longest", "context:source:match:longest", {contextPointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextSourceMatchNamed<context_phrase::Longest>));
    declareHostFunction(context, "Context:source_match_longest", "Context:source_match_longest", {contextPointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextSourceMatchNamed<context_phrase::Longest>));

    declareHostFunction(context, SyntaxDictionary, "context:syntax:dictionary", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxDictionary));
    declareHostFunction(context, SyntaxActive, "context:syntax:active", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxActive));
    declareHostFunction(context, SyntaxData, "context:syntax:data", {contextPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxData));
    declareHostFunction(context, SyntaxBytes, "context:syntax:bytes", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxBytes));
    declareHostFunction(context, SyntaxAdvance, "context:syntax:advance", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxAdvance));
    declareHostFunction(context, SyntaxEmit, "context:syntax:emit$text", {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxEmitText));
    declareHostFunction(context, SyntaxEmit, "context:syntax:emit", {contextPointer, bytePointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxEmit));
    declareHostFunction(context, SyntaxCopy, "context:syntax:copy", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxCopy));
    declareHostFunction(context, SyntaxMatch, "context:syntax:match", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxMatch));
    declareHostFunction(context, SyntaxElaborate, "context:syntax:elaborate", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxElaborate));
    declareHostFunction(context, "context:syntax:match:exact", "context:syntax:match:exact", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxMatchNamed<context_phrase::Exact>));
    declareHostFunction(context, "context:syntax:match:first", "context:syntax:match:first", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxMatchNamed<context_phrase::First>));
    declareHostFunction(context, "context:syntax:match:longest", "context:syntax:match:longest", {contextPointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextSyntaxMatchNamed<context_phrase::Longest>));
    declareHostFunction(context, "Context:syntax_match_longest", "Context:syntax_match_longest", {contextPointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextSyntaxMatchNamed<context_phrase::Longest>));
    declareHostFunction(context, SyntaxPath, "context:syntax:path", {contextPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxPath));
    declareHostFunction(context, SyntaxLine, "context:syntax:line", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxLine));
    declareHostFunction(context, SyntaxPosition, "context:syntax:position", {contextPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSyntaxPosition));
    declareHostFunction(context, BlockCapture, "context:source:block:capture", {contextPointer}, sourceBlockPointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockCapture));
    declareHostFunction(context, BlockHeader, "context:source:block:header", {sourceBlockPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockHeader));
    declareHostFunction(context, BlockBody, "context:source:block:body", {sourceBlockPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockBody));
    declareHostFunction(context, BlockPath, "context:source:block:path", {sourceBlockPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockPath));
    declareHostFunction(context, BlockHeaderLine, "context:source:block:header:line", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockHeaderLine));
    declareHostFunction(context, BlockHeaderPosition, "context:source:block:header:position", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockHeaderPosition));
    declareHostFunction(context, BlockLine, "context:source:block:line", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockLine));
    declareHostFunction(context, BlockPosition, "context:source:block:position", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockPosition));
    declareHostFunction(context, BlockExecute, "context:source:block:execute",
                        {contextPointer, sourceBlockPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockExecute));
    declareHostFunction(context, "context:source:block:execute:current", "context:source:block:execute:current",
                        {contextPointer, sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockExecuteNamed<false>));
    declareHostFunction(context, "context:source:block:execute:scoped", "context:source:block:execute:scoped",
                        {contextPointer, sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockExecuteNamed<true>));
    declareHostFunction(context, BlockRelease, "context:source:block:release", {sourceBlockPointer}, voidType,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockRelease));
    declareHostFunction(context, "Context:source_block_capture", "Context:source_block_capture", {contextPointer},
                        sourceBlockPointer, reinterpret_cast<std::uintptr_t>(&contextSourceBlockCapture));
    declareHostFunction(context, "Context:source_block_execute_current", "Context:source_block_execute_current",
                        {contextPointer, sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockExecuteNamed<false>));
    declareHostFunction(context, "Context:source_block_execute_scoped", "Context:source_block_execute_scoped",
                        {contextPointer, sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockExecuteNamed<true>));
    declareHostFunction(context, "SourceBlock:header", "SourceBlock:header", {sourceBlockPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockHeader));
    declareHostFunction(context, "SourceBlock:body", "SourceBlock:body", {sourceBlockPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockBody));
    declareHostFunction(context, "SourceBlock:path", "SourceBlock:path", {sourceBlockPointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockPath));
    declareHostFunction(context, "SourceBlock:header_line", "SourceBlock:header_line", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockHeaderLine));
    declareHostFunction(context, "SourceBlock:header_position", "SourceBlock:header_position", {sourceBlockPointer},
                        u64, reinterpret_cast<std::uintptr_t>(&contextSourceBlockHeaderPosition));
    declareHostFunction(context, "SourceBlock:line", "SourceBlock:line", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockLine));
    declareHostFunction(context, "SourceBlock:position", "SourceBlock:position", {sourceBlockPointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockPosition));
    declareHostFunction(context, "SourceBlock:release", "SourceBlock:release", {sourceBlockPointer}, voidType,
                        reinterpret_cast<std::uintptr_t>(&contextSourceBlockRelease));
    declareHostFunction(context, DiagnosticError, "context:diagnostic:error", {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextDiagnosticError));
    declareHostFunction(context, DiagnosticErrorAt, "context:diagnostic:error:at",
                        {contextPointer, bytePointer, u64, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextDiagnosticErrorAt));
    declareHostFunction(context, ExpressionFormat, "context:expression:format$text", {contextPointer, bytePointer},
                        bytePointer, reinterpret_cast<std::uintptr_t>(&contextExpressionFormatText));
    declareHostFunction(context, ExpressionFormat, "context:expression:format$slice",
                        {contextPointer, bytePointer, u64, u64}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextExpressionFormat));
    declareHostFunction(context, ExpressionFormatAt, "context:expression:format:at",
                        {contextPointer, bytePointer, u64, u64, bytePointer, u64, u64}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextExpressionFormatAt));
    declareHostFunction(context, ValueContains, "context:value:contains", {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextValueContains));
    declareHostFunction(context, ValueFormat, "context:value:format", {contextPointer, bytePointer}, bytePointer,
                        reinterpret_cast<std::uintptr_t>(&contextValueFormat));
    declareHostFunction(context, ValueDefineText, "context:value:define:text",
                        {contextPointer, bytePointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextValueDefineText));
    declareHostFunction(context, ValueDefineInteger, "context:value:define:integer", {contextPointer, bytePointer, i64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextValueDefineInteger));
    declareHostFunction(context, ValueAssignText, "context:value:assign:text",
                        {contextPointer, bytePointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextValueAssignText));
    declareHostFunction(context, ValueAssignInteger, "context:value:assign:integer", {contextPointer, bytePointer, i64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextValueAssignInteger));

    declareHostFunction(context, TypeFind, "context:type:find", {contextPointer, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeFind));
    declareHostFunction(context, TypeGet, "context:type:get", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGet));
    declareHostFunction(context, "context:type:kind", "context:type:kind", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::Kind>));
    declareHostFunction(context, "context:type:size", "context:type:size", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::Size>));
    declareHostFunction(context, "context:type:alignment", "context:type:alignment", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::Alignment>));
    declareHostFunction(context, "context:type:signed", "context:type:signed", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::Signed>));
    declareHostFunction(context, "context:type:element", "context:type:element", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::Element>));
    declareHostFunction(context, "context:type:element:count", "context:type:element:count", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::ElementCount>));
    declareHostFunction(context, "context:type:pointer:depth", "context:type:pointer:depth", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::PointerDepth>));
    declareHostFunction(context, "context:type:result", "context:type:result", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeGetNamed<context_type::Result>));
    declareHostFunction(context, TypeInteger, "context:type:integer", {contextPointer, bytePointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeInteger));
    declareHostFunction(context, "context:type:integer:signed", "context:type:integer:signed",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeIntegerNamed<true>));
    declareHostFunction(context, "context:type:integer:unsigned", "context:type:integer:unsigned",
                        {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeIntegerNamed<false>));
    declareHostFunction(context, TypeFloating, "context:type:floating", {contextPointer, bytePointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeFloating));
    declareHostFunction(context, TypePointer, "context:type:pointer", {contextPointer, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypePointer));
    declareHostFunction(context, TypeArray, "context:type:array", {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeArray));
    declareHostFunction(context, TypeDeclareStructure, "context:type:structure:declare", {contextPointer, bytePointer},
                        u64, reinterpret_cast<std::uintptr_t>(&contextTypeDeclareStructure));
    declareHostFunction(context, TypeCompleteStructure, "context:type:structure:complete",
                        {contextPointer, u64, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeCompleteStructure));
    declareHostFunction(context, "context:type:structure:complete:natural", "context:type:structure:complete:natural",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeCompleteStructureNatural<false>));
    declareHostFunction(context, "context:type:structure:complete:packed", "context:type:structure:complete:packed",
                        {contextPointer, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeCompleteStructureNatural<true>));
    declareHostFunction(context, "context:type:structure:complete:aligned", "context:type:structure:complete:aligned",
                        {contextPointer, u64, u64, u64}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeCompleteStructureAligned));
    declareHostFunction(context, TypeFunction, "context:type:function", {contextPointer, u64, u64, bytePointer, u64},
                        u64, reinterpret_cast<std::uintptr_t>(&contextTypeFunction));
    declareHostFunction(context, "context:type:function:fixed", "context:type:function:fixed",
                        {contextPointer, u64, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeFunctionNamed<false>));
    declareHostFunction(context, "context:type:function:variadic", "context:type:function:variadic",
                        {contextPointer, u64, u64, bytePointer}, u64,
                        reinterpret_cast<std::uintptr_t>(&contextTypeFunctionNamed<true>));
  }
} // namespace recurloop
