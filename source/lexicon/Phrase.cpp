#if !defined(__LEXICON_PHRASE_CPP)
  #define __LEXICON_PHRASE_CPP
  #include <context/Context.hpp>
  #include <lexicon/Lexicon.hpp>
  #include <lexicon/Draft.hpp>

namespace lexicon {
  using phrase::Contains;

  namespace {
    class TimingScope {
    public:
      TimingScope(context::Exec::Timing &timing, std::chrono::nanoseconds &total, std::uint64_t &count)
          : timing(timing), total(total), count(count), generation(timing.generation), start(now()) {}

      ~TimingScope() {
        if (timing.generation == generation) {
          total += std::chrono::duration_cast<std::chrono::nanoseconds>(now() - start);
          ++count;
        }
      }

    private:
      using Clock = std::chrono::high_resolution_clock;

      static Clock::time_point now() {
        return Clock::now();
      }

      context::Exec::Timing &timing;
      std::chrono::nanoseconds &total;
      std::uint64_t &count;
      std::uint64_t generation;
      Clock::time_point start;
    };
  } // namespace

  namespace phrase::type {
    void action(context::Context &context, Phrase &phrase) {
      Phrase::Action action = phrase.getAction();
      if (action == nullptr)
        THROW(, "Cannot execute phrase, action is null for phrase: '" << phrase.getKeyEscaped() << "'.")
      action(context, phrase);
    }

    Behavior getBehavior(Phrase &phrase) {
      Phrase type = phrase.getType();
      if (type.isNull()) THROW(, "Phrase has no type: '" << phrase.getKeyEscaped() << "'.")

      Behavior behavior;
      type.fetch(0, behavior);
      return behavior;
    }

    static Core getCore(Phrase &phrase) {
      Phrase data = getData(phrase);

      Core core;
      data.fetch(sizeof(Behavior), core);
      return core;
    }

    Phrase getData(Phrase &phrase) {
      Phrase type = phrase.getType();
      if (type.isNull()) THROW(, "Phrase has no type: '" << phrase.getKeyEscaped() << "'.")

      Phrase data = type.getType();
      if (data.isNull()) THROW(, "Phrase type has no data type: '" << type.getKeyEscaped() << "'.")
      return data;
    }

    Phrase getElaborate(Phrase &phrase) {
      return Phrase(phrase.getLexicon(), getCore(phrase).elaborate).load();
    }

    Phrase getCallable(Phrase &phrase) {
      return Phrase(phrase.getLexicon(), getCore(phrase).callable).load();
    }

    Phrase getScopedCallable(Phrase &phrase) {
      return Phrase(phrase.getLexicon(), getCore(phrase).scopedCallable).load();
    }
  } // namespace phrase::type

  // core phrase methods
  Phrase::Phrase(radix::Item item) : radix::Item(item) {};

  Phrase::~Phrase() {
    if (!meta.saved) save();
  }

  Lexicon *Phrase::getLexicon() {
    return (Lexicon *)getRadix();
  }

  std::string Phrase::getKey() {
    auto node = getNode();
    auto bits = node.keyBits();

    try {
      std::vector<char> key(Bit::bytes(bits), '\0');
      node.keyCopy(Bit(key.data(), 0), bits);
      return std::string(key.begin(), key.end());
    } catch (const std::bad_alloc &e) {
      THROW(, "Cannot get phrase key, out of memory (phrase " << getAddress() << ", key bits " << bits << ").");
    }
  }

  std::string Phrase::getKeyEscaped() {
    return helper::string::escape(getKey());
  }

  bool Phrase::containsSubdictionary() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::SUBDICTIONARY;
  }

  Dictionary Phrase::getSubdictionary() {
    if (!meta.loaded) load();
    return Dictionary(getLexicon(), cached.subdictionary);
  }

  bool Phrase::containsParent() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::PARENT;
  }

  Phrase &Phrase::setParent(Phrase parent) {
    const auto address = parent.getAddress();
    if (cached.parent == address) return *this;
    if (!containsParent()) THROW(, "Phrase doesnt contain parent, so it cannot be set.")

    meta.saved = false;
    cached.parent = address;
    return *this;
  }

  Phrase Phrase::getParent() {
    if (!meta.loaded) load();
    return Phrase(getLexicon(), cached.parent).load();
  }

  bool Phrase::containsPrototype() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::PROTOTYPE;
  }

  Phrase &Phrase::setPrototype(Phrase prototype) {
    auto address = prototype.getAddress();

    if (cached.prototype == address) return *this;

    if (!containsPrototype()) THROW(, "Phrase doesnt contain prototype, so it cannot be set.");

    meta.saved = false;
    cached.prototype = address;

    return *this;
  }

  Phrase Phrase::getPrototype() {
    if (!meta.loaded) load();
    return Phrase(getLexicon(), cached.prototype).load();
  }

  bool Phrase::containsType() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::TYPE;
  }

  Phrase &Phrase::setType(Phrase type) {
    auto address = type.getAddress();
    if (cached.type == address) return *this;
    if (!containsType()) THROW(, "Phrase doesnt contain type, so it cannot be set.");

    meta.saved = false;
    cached.type = address;
    return *this;
  }

  Phrase Phrase::getType() {
    if (!meta.loaded) load();
    return Phrase(getLexicon(), cached.type).load();
  }

  bool Phrase::containsAction() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::ACTION;
  }

  Phrase &Phrase::setAction(Action action) {
    if (cached.action.dispatch == action && cached.action.implementation == 0 && cached.action.entry == 0) return *this;
    if (!containsAction()) THROW(, "Phrase doesnt contain action, so it cannot be set.");

    meta.saved = false;
    cached.action = {action, 0, 0};
    return *this;
  }

  Phrase::Action Phrase::getAction() {
    if (!meta.loaded) load();
    return cached.action.dispatch;
  }

  Phrase &Phrase::setActionImplementation(Phrase implementation) {
    if (!containsAction()) THROW(, "Phrase doesnt contain action, so its implementation cannot be set.");
    const Size address = implementation.getAddress();
    if (cached.action.implementation == address && cached.action.entry == 0) return *this;
    meta.saved = false;
    cached.action.implementation = address;
    cached.action.entry = 0;
    return *this;
  }

  Phrase Phrase::getActionImplementation() {
    if (!meta.loaded) load();
    return Phrase(getLexicon(), cached.action.implementation).load();
  }

  Phrase &Phrase::setActionEntry(std::uintptr_t entry) {
    if (!containsAction()) THROW(, "Phrase doesnt contain action, so its entry cannot be set.");
    if (cached.action.entry == entry) return *this;
    meta.saved = false;
    cached.action.entry = entry;
    return *this;
  }

  std::uintptr_t Phrase::getActionEntry() {
    if (!meta.loaded) load();
    return cached.action.entry;
  }

  bool Phrase::containsSuccessor() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::SUCCESSOR;
  }

  Phrase &Phrase::setSuccessor(Phrase successor) {
    auto address = successor.getAddress();

    if (cached.successor == address) return *this;

    if (!containsSuccessor()) THROW(, "Phrase doesnt contain successor, so it cannot be set.");

    meta.saved = false;
    cached.successor = address;

    return *this;
  }

  Phrase Phrase::getSuccessor() {
    if (!meta.loaded) load();

    return Phrase(getLexicon(), cached.successor);
  }

  bool Phrase::isSerializable() {
    if (!meta.loaded) load();
    return !(cached.contains & phrase::Contains::UNSERIALIZABLE);
  }

  Phrase &Phrase::setSerializable(bool serializable) {
    if (!meta.loaded) load();
    const bool current = !(cached.contains & phrase::Contains::UNSERIALIZABLE);
    if (current == serializable) return *this;

    meta.saved = false;
    if (serializable)
      cached.contains = static_cast<Contains>(static_cast<std::uint16_t>(cached.contains) &
                                              ~static_cast<std::uint16_t>(Contains::UNSERIALIZABLE));
    else
      cached.contains |= Contains::UNSERIALIZABLE;
    return *this;
  }

  bool Phrase::isPermanent() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::PERMANENT;
  }

  Phrase &Phrase::setPermanent(bool permanent) {
    if (!meta.loaded) load();
    const bool current = cached.contains & phrase::Contains::PERMANENT;
    if (current == permanent) return *this;
    if (current) THROW(, "Permanent phrase '" << getKeyEscaped() << "' cannot be made mutable.")

    meta.saved = false;
    cached.contains |= Contains::PERMANENT;
    return *this;
  }

  bool Phrase::isRewritable() {
    if (!meta.loaded) load();
    return cached.contains & phrase::Contains::REWRITABLE;
  }

  Phrase &Phrase::setRewritable(bool rewritable) {
    if (!meta.loaded) load();
    const bool current = cached.contains & phrase::Contains::REWRITABLE;
    if (current == rewritable) return *this;

    meta.saved = false;
    if (rewritable)
      cached.contains |= Contains::REWRITABLE;
    else
      cached.contains = static_cast<Contains>(static_cast<std::uint16_t>(cached.contains) &
                                              ~static_cast<std::uint16_t>(Contains::REWRITABLE));
    return *this;
  }

  bool Phrase::isElaboratable() {
    if (!meta.loaded) load();

    if (getType().isNull()) return false;
    return phrase::type::getBehavior(*this).elaborate != nullptr;
  }

  bool Phrase::isInvokable() {
    if (!meta.loaded) load();

    if (getType().isNull()) return false;
    return phrase::type::getBehavior(*this).invoke != nullptr;
  }

  void Phrase::elaborate(context::Context &context) {
    TimingScope timing(context.exec.timing, context.exec.timing.elaborate, context.exec.timing.elaborateCount);
    if (!meta.loaded) load();

    phrase::type::Behavior behavior = phrase::type::getBehavior(*this);
    phrase::type::Dispatch dispatch = behavior.elaborate;
    if (dispatch == nullptr)
      THROW(, "Cannot elaborate phrase, type is not elaboratable for phrase: '" << getKeyEscaped() << "'.")

    lexicon::Phrase *previous = context.exec.invoked;
    context.exec.invoked = this;
    try {
      dispatch(context, *this);
      detail::rethrowPendingPhraseException(context);
    } catch (...) {
      context.exec.invoked = previous;
      throw;
    }
    if (context.exec.invoked != nullptr) context.exec.invoked = previous;
  }

  void Phrase::invoke(context::Context &context) {
    TimingScope timing(context.exec.timing, context.exec.timing.invoke, context.exec.timing.invokeCount);
    if (!meta.loaded) load();

    phrase::type::Behavior behavior = phrase::type::getBehavior(*this);
    if (behavior.invoke == nullptr)
      THROW(, "Cannot invoke phrase, type is not callable for phrase: '" << getKeyEscaped() << "'.")

    lexicon::Phrase *previous = context.exec.invoked;
    context.exec.invoked = this;
    try {
      behavior.invoke(context, *this);
      detail::rethrowPendingPhraseException(context);
    } catch (...) {
      context.exec.invoked = previous;
      throw;
    }
    if (context.exec.invoked != nullptr) context.exec.invoked = previous;
  }

  Byte Phrase::allocate(Size bytes) {
    if (isNull()) THROW(, "Cannot allocate memory, phrase is null.")

    Byte byte = radix::Item::allocate(bytes);
    if (byte.isNull())
      THROW(, "Cannot allocate memory for phrase '" << getKeyEscaped() << "', phrase must be the last one in lexicon.")
    return byte;
  }

  Byte Phrase::content(Size offset, Size bytes) {
    if (isNull()) THROW(, "Cannot get content, phrase is null.")
    return radix::Item::content(offset + meta.size, bytes);
  }

  Size Phrase::metadataSize() {
    if (!meta.loaded) load();
    return meta.size;
  }

  Size Phrase::payloadSize() {
    if (!meta.loaded) load();
    const Size total = radix::Item::contentSize();
    if (total < meta.size) THROW(, "Phrase content is shorter than its metadata.")
    return total - meta.size;
  }

  Phrase &Phrase::save(bool init) {
    if (isNull()) return *this;

    *(phrase::Contains *)(radix::Item::content(0, sizeof(phrase::Contains)).toPtr()) = cached.contains;

    Size offset = sizeof(phrase::Contains);

    if (cached.contains & Contains::PROTOTYPE) {
      *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr()) = cached.prototype;
      offset += sizeof(Size);
    }

    if (cached.contains & Contains::PARENT) {
      *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr()) = cached.parent;
      offset += sizeof(Size);
    }

    if (cached.contains & Contains::SUBDICTIONARY) {
      if (init) *(radix::node::Data *)(radix::Item::content(offset, sizeof(radix::node::Data)).toPtr()) = {};
      offset += sizeof(radix::node::Data);
    }

    if (cached.contains & Contains::TYPE) {
      *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr()) = cached.type;
      offset += sizeof(Size);
    }

    if (cached.contains & Contains::ACTION) {
      *(ActionBinding *)(radix::Item::content(offset, sizeof(ActionBinding)).toPtr()) = cached.action;
      offset += sizeof(ActionBinding);
    }

    if (cached.contains & Contains::SUCCESSOR) {
      *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr()) = cached.successor;
      offset += sizeof(Size);
    }

    meta.saved = true;
    meta.loaded = true;

    return *this;
  }

  Phrase &Phrase::load() {
    if (isNull()) return *this;

    cached.contains = *(Contains *)(radix::Item::content(0, sizeof(Contains)).toPtr());

    Size offset = sizeof(Contains);

    if (cached.contains & Contains::PROTOTYPE) {
      cached.prototype = *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr());
      offset += sizeof(Size);
    } else
      cached.prototype = 0;

    auto prototype = Phrase(getLexicon(), cached.prototype).load();

    if (cached.contains & Contains::PARENT) {
      cached.parent = *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr());
      offset += sizeof(Size);
    } else
      cached.parent = prototype.cached.parent;

    if (cached.contains & Contains::SUBDICTIONARY) {
      cached.subdictionary =
          ((radix::node::Data *)(radix::Item::content(offset, sizeof(radix::node::Data)).toPtr()))->address(getRadix());
      offset += sizeof(radix::node::Data);
    } else
      cached.subdictionary = prototype.cached.subdictionary;

    if (cached.contains & Contains::TYPE) {
      cached.type = *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr());
      offset += sizeof(Size);
    } else
      cached.type = prototype.cached.type;

    if (cached.contains & Contains::ACTION) {
      cached.action = *(ActionBinding *)(radix::Item::content(offset, sizeof(ActionBinding)).toPtr());
      offset += sizeof(ActionBinding);
    } else
      cached.action = prototype.cached.action;

    if (cached.contains & Contains::SUCCESSOR) {
      cached.successor = *(Size *)(radix::Item::content(offset, sizeof(Size)).toPtr());
      offset += sizeof(Size);
    } else
      cached.successor = prototype.cached.successor;

    meta.saved = true;
    meta.loaded = true;
    meta.size = offset;

    return *this;
  }

  // forwarded dictionary methods
  Dictionary Phrase::append(Byte key, Size keyOffset, Size keyBits) {
    return getSubdictionary().append(key, keyOffset, keyBits);
  }

  Dictionary Phrase::append(std::string key) {
    return getSubdictionary().append(Byte((char *)key.c_str()), 0, key.size() * Byte::length);
  }

  Draft Phrase::make() {
    return getSubdictionary().make();
  }

  Draft Phrase::make(Action action) {
    return getSubdictionary().make(action);
  }

  Draft Phrase::make(Phrase prototype) {
    return getSubdictionary().make(prototype);
  }

  Phrase Phrase::push() {
    return getSubdictionary().push();
  }

  Match Phrase::matchFirst(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter) {
    return getSubdictionary().matchFirst(key, keyOffset, keyBits, filter);
  }

  Match Phrase::matchLongest(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter) {
    return getSubdictionary().matchLongest(key, keyOffset, keyBits, filter);
  }

  Match Phrase::matchExact(Byte key, Size keyOffset, Size keyBits, radix::match::Filter filter) {
    return getSubdictionary().matchExact(key, keyOffset, keyBits, filter);
  }

  Dictionary Phrase::predecessor(radix::node::Filter filter) {
    return getSubdictionary().predecessor(filter);
  }

  Dictionary Phrase::fore(radix::node::Filter filter) {
    return getSubdictionary().fore(filter);
  }

  Dictionary Phrase::rear(radix::node::Filter filter) {
    return getSubdictionary().rear(filter);
  }

  Dictionary Phrase::prev(radix::node::Filter filter) {
    return getSubdictionary().prev(filter);
  }

  Dictionary Phrase::next(radix::node::Filter filter) {
    return getSubdictionary().next(filter);
  }

  Dictionary Phrase::foreInverse(radix::node::Filter filter) {
    return getSubdictionary().foreInverse(filter);
  }

  Dictionary Phrase::rearInverse(radix::node::Filter filter) {
    return getSubdictionary().rearInverse(filter);
  }

  Dictionary Phrase::prevInverse(radix::node::Filter filter) {
    return getSubdictionary().prevInverse(filter);
  }

  Dictionary Phrase::nextInverse(radix::node::Filter filter) {
    return getSubdictionary().nextInverse(filter);
  }

  Phrase Phrase::older(radix::item::Filter filter) {
    return Phrase(radix::Item::prev(filter)).load();
  }

  Phrase Phrase::newer(radix::item::Filter filter) {
    return Phrase(radix::Item::next(filter)).load();
  }
} // namespace lexicon

#endif
