#pragma once

#include "_module_classes.hpp"
#include "Dictionary.hpp"
#include <utilities/Declaration.hpp>

namespace lexicon {
  namespace detail {
    void rethrowPendingPhraseException(context::Context &context);
  }

  namespace phrase::type {
    using Dispatch = void (*)(context::Context &context, Phrase &phrase);

    struct Behavior {
      Dispatch elaborate = nullptr;
      Dispatch invoke = nullptr;
    };

    struct Core {
      Size elaborate = 0;
      Size callable = 0;
      Size scopedCallable = 0;
    };

    void action(context::Context &context, Phrase &phrase);

    Behavior getBehavior(Phrase &phrase);
    Phrase getData(Phrase &phrase);
    Phrase getElaborate(Phrase &phrase);
    Phrase getCallable(Phrase &phrase);
    Phrase getScopedCallable(Phrase &phrase);
  } // namespace phrase::type

  class Phrase : public radix::Item {
  public:
    using radix::Item::Item;
    using Action = void (*)(context::Context &context, Phrase &invoked);
    using Contains = phrase::Contains;

    struct ActionBinding {
      Action dispatch = nullptr;
      Size implementation = 0;
      std::uintptr_t entry = 0;
    };

  public:
    DECLARATION Phrase(radix::Item item);
    DECLARATION ~Phrase();

    DECLARATION Lexicon *getLexicon();

    DECLARATION std::string getKey();
    DECLARATION std::string getKeyEscaped();

    DECLARATION bool containsSubdictionary();
    DECLARATION Dictionary getSubdictionary();
    DECLARATION bool containsParent();
    DECLARATION Phrase &setParent(Phrase parent);
    DECLARATION Phrase getParent();

    DECLARATION bool containsPrototype();
    DECLARATION Phrase &setPrototype(Phrase prototype);
    DECLARATION Phrase getPrototype();

    DECLARATION bool containsType();
    DECLARATION Phrase &setType(Phrase type);
    DECLARATION Phrase getType();

    DECLARATION bool containsAction();
    DECLARATION Phrase &setAction(Action action);
    DECLARATION Action getAction();
    DECLARATION Phrase &setActionImplementation(Phrase implementation);
    DECLARATION Phrase getActionImplementation();
    DECLARATION Phrase &setActionEntry(std::uintptr_t entry);
    DECLARATION std::uintptr_t getActionEntry();

    DECLARATION bool containsSuccessor();
    DECLARATION Phrase &setSuccessor(Phrase successor);
    DECLARATION Phrase getSuccessor();

    DECLARATION bool isSerializable();
    DECLARATION Phrase &setSerializable(bool serializable);
    DECLARATION bool isPermanent();
    DECLARATION Phrase &setPermanent(bool permanent);
    DECLARATION bool isRewritable();
    DECLARATION Phrase &setRewritable(bool rewritable);

    DECLARATION bool isElaboratable();
    DECLARATION bool isInvokable();
    DECLARATION void elaborate(context::Context &context);
    DECLARATION void invoke(context::Context &context);

    DECLARATION Byte allocate(Size bytes);
    DECLARATION Byte content(Size offset, Size bytes);
    DECLARATION Size metadataSize();
    DECLARATION Size payloadSize();

    DECLARATION Phrase &save(bool init = false);
    DECLARATION Phrase &load();

  public: // Forwarded from dictionary
    DECLARATION Dictionary append(Byte key, Size keyOffset, Size keyBits);
    DECLARATION Dictionary append(std::string key);
    DECLARATION Draft make();
    DECLARATION Draft make(Action action);
    DECLARATION Draft make(Phrase prototype);
    DECLARATION Phrase push();

    DECLARATION Match matchFirst(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter = nullptr);
    DECLARATION Match matchLongest(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter = nullptr);
    DECLARATION Match matchExact(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter = nullptr);

    DECLARATION Dictionary predecessor(radix::node::Filter filter = nullptr);

    DECLARATION Dictionary fore(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary rear(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary prev(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary next(radix::node::Filter filter = nullptr);

    DECLARATION Dictionary foreInverse(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary rearInverse(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary prevInverse(radix::node::Filter filter = nullptr);
    DECLARATION Dictionary nextInverse(radix::node::Filter filter = nullptr);

    DECLARATION Phrase older(radix::item::Filter filter = nullptr);
    DECLARATION Phrase newer(radix::item::Filter filter = nullptr);

  public:
    template <Size N> DECLARATION Dictionary append(const char (&str)[N]);
    template <typename... Args> DECLARATION Phrase &store(const Args &...args);
    template <typename... Args> DECLARATION Phrase &update(Size offset, const Args &...args);
    template <typename... Args> DECLARATION Phrase &fetch(Size offset, Args &...args);

  protected:
    struct {
      bool saved = true, loaded = false;
      Size size = sizeof(phrase::Contains);
    } meta = {};

    struct {
      phrase::Contains contains = phrase::Contains::EMPTY;
      Size parent = 0, subdictionary = 0, prototype = 0, type = 0, successor = 0;
      ActionBinding action;
    } cached = {};

    friend class Draft;
  };

  template <Size N> Dictionary Phrase::append(const char (&str)[N]) {
    return append(Byte((unsigned char *)str), 0, (N - 1) * Byte::length);
  }

  template <typename... Args> Phrase &Phrase::store(const Args &...args) {
    ((*(Args *)allocate(sizeof(Args)).toPtr() = args), ...);
    return *this;
  }

  template <typename... Args> Phrase &Phrase::update(Size offset, const Args &...args) {
    ((*(Args *)content(offset, sizeof(Args)).toPtr() = args, offset += sizeof(Args)), ...);
    return *this;
  }

  template <typename... Args> Phrase &Phrase::fetch(Size offset, Args &...args) {
    ((args = *(Args *)content(offset, sizeof(Args)).toPtr(), offset += sizeof(Args)), ...);
    return *this;
  }
} // namespace lexicon
