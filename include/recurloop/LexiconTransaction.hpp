#pragma once

#include <lexicon/Lexicon.hpp>
#include <radix/Checkpoint.hpp>
#include <utilities/Size.hpp>

#include <span>

namespace context { class Context; }
namespace lexicon { class Phrase; }

namespace recurloop {
  // One rollback watermark over the shared RecurLoop lexicon.
  //
  // This transaction is for compile-time/elaboration semantic state stored in
  // context.lexicon: language phrases, compiler registries, types, modules,
  // compile-time values and other serializable compiler objects.
  //
  // It is NOT a runtime scope mechanism for compiled functions. Function
  // locals, if/while blocks and ordinary assignments are lowered to generated
  // code and do not checkpoint the lexicon unless the program explicitly calls
  // Context/Phrase/Lexicon APIs.
  //
  // rollback is the default. commit() keeps the complete post-checkpoint radix
  // range. It is not selective promotion and must not be used to make one
  // declaration escape a transaction while discarding its neighbours.
  class LexiconTransaction {
  public:
    // Capture/restore helpers are for transaction owners whose lifetime spans
    // separate parser callbacks. They preserve the exact same radix watermark
    // semantics as the RAII form without allocating a second transaction stack.
    static Size capture(lexicon::Lexicon &lexicon) {
      return lexicon.checkpoint().getAddress();
    }

    static void restore(lexicon::Lexicon &lexicon, Size checkpointAddress) noexcept {
      radix::Checkpoint(&lexicon, checkpointAddress).restore();
    }

    explicit LexiconTransaction(lexicon::Lexicon &lexicon)
        : lexicon(&lexicon), checkpointAddress(capture(lexicon)) {}

    LexiconTransaction(const LexiconTransaction &) = delete;
    LexiconTransaction &operator=(const LexiconTransaction &) = delete;

    LexiconTransaction(LexiconTransaction &&other) noexcept
        : lexicon(other.lexicon), checkpointAddress(other.checkpointAddress), active(other.active) {
      other.active = false;
    }

    LexiconTransaction &operator=(LexiconTransaction &&) = delete;

    ~LexiconTransaction() {
      rollback();
    }

    Size checkpoint() const {
      return checkpointAddress;
    }

    bool isActive() const {
      return active;
    }

    void rollback() noexcept {
      if (!active) return;
      restore(*lexicon, checkpointAddress);
      active = false;
    }

    void commit() noexcept {
      active = false;
    }

    // Preserve only the selected semantic graph while discarding every other
    // allocation made by this transaction. This is the selective counterpart
    // to commit(): capture selected state, rollback to the watermark, replay
    // only that state into the parent lexicon.
    void promote(context::Context &context, std::span<const lexicon::Phrase> roots);

  private:
    lexicon::Lexicon *lexicon;
    Size checkpointAddress;
    bool active = true;
  };
} // namespace recurloop
