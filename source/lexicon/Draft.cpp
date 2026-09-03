#if !defined(__LEXICON_DRAFT_CPP)
  #define __LEXICON_DRAFT_CPP
  #include <lexicon/Lexicon.hpp>

namespace lexicon {
  Draft::Draft() : Dictionary(), phrase() {}

  Draft::Draft(Dictionary dictionary) : Dictionary(dictionary), phrase(dictionary.getRadix()) {
    Phrase existing = dictionary.getPhrase();
    if (!existing.isNull() && existing.isPermanent())
      THROW(, "Cannot redefine permanent phrase '" << existing.getKeyEscaped() << "'.")
  }

  Draft::Draft(Dictionary dictionary, Action action) : Draft(dictionary) {
    phrase.cached.action.dispatch = action;
    phrase.cached.contains |= phrase::Contains::ACTION;
    phrase.meta.size += sizeof(Phrase::ActionBinding);
  }

  Draft::Draft(Dictionary dictionary, Phrase prototype) : Draft(dictionary) {
    Phrase temp = prototype.getPrototype();
    if (!temp.isNull()) prototype = temp;

    phrase.cached.prototype = prototype.getAddress();
    phrase.cached.contains |= phrase::Contains::PROTOTYPE;
    phrase.meta.size += sizeof(Size);

    phrase.cached.action = prototype.cached.action;
    phrase.cached.action.entry = 0;
    phrase.cached.contains |= phrase::Contains::ACTION;
    phrase.meta.size += sizeof(Phrase::ActionBinding);
  }

  Draft::Draft(Dictionary dictionary, Phrase phrase, Action action) : Dictionary(dictionary), phrase(phrase) {
    phrase.cached.action.dispatch = action;
    phrase.cached.contains |= phrase::Contains::ACTION;
    phrase.meta.size += sizeof(Phrase::ActionBinding);
  }

  Draft::Draft(Dictionary dictionary, Phrase phraseClone, Phrase prototype)
      : Dictionary(dictionary), phrase(phraseClone) {
    Phrase temp = prototype.getPrototype();
    if (!temp.isNull()) prototype = temp;

    phrase.cached.prototype = prototype.getAddress();
    phrase.cached.contains |= phrase::Contains::PROTOTYPE;
    phrase.meta.size += sizeof(Size);

    phrase.cached.action = prototype.cached.action;
    phrase.cached.action.entry = 0;
    phrase.cached.contains |= phrase::Contains::ACTION;
    phrase.meta.size += sizeof(Phrase::ActionBinding);
  }

  Draft::Draft(Draft &draft) : Dictionary(draft), phrase(draft.phrase) {}

  Draft &Draft::append(Byte key, Size keyOffset, Size keyBits) {
    static_cast<Dictionary &>(*this) = Dictionary::append(key, keyOffset, keyBits);
    Phrase existing = getPhrase();
    if (!existing.isNull() && existing.isPermanent())
      THROW(, "Cannot redefine permanent phrase '" << existing.getKeyEscaped() << "'.")
    return *this;
  }

  bool Draft::containsSubdictionary() {
    return phrase.containsSubdictionary();
  }

  Draft &Draft::enableSubdictionary() {
    if (!containsSubdictionary()) {
      phrase.cached.contains |= phrase::Contains::SUBDICTIONARY;
      phrase.meta.size += sizeof(radix::node::Data);
    }

    return *this;
  }

  bool Draft::containsParent() {
    return phrase.containsParent();
  }

  Draft &Draft::setParent(Phrase parent) {
    if (!containsParent()) {
      phrase.cached.contains |= phrase::Contains::PARENT;
      phrase.meta.size += sizeof(Size);
    }

    phrase.setParent(parent);
    return *this;
  }

  Phrase Draft::getParent() {
    return phrase.getParent();
  }

  bool Draft::containsPrototype() {
    return phrase.containsPrototype();
  }

  Draft &Draft::setPrototype(Phrase prototype) {
    if (!(phrase.cached.contains & phrase::Contains::PROTOTYPE)) {
      phrase.cached.contains |= phrase::Contains::PROTOTYPE;
      phrase.meta.size += sizeof(Size);
    }

    phrase.setPrototype(prototype);

    return *this;
  }

  Phrase Draft::getPrototype() {
    return phrase.getPrototype();
  }

  bool Draft::containsType() {
    return phrase.containsType();
  }

  Draft &Draft::setType(Phrase type) {
    if (!containsType()) {
      phrase.cached.contains |= phrase::Contains::TYPE;
      phrase.meta.size += sizeof(Size);
    }

    phrase.setType(type);
    return *this;
  }

  Draft &Draft::setDefaultType(Phrase data, Phrase elaborate) {
    if (!containsType()) setType(phrase.cached.action.dispatch == nullptr ? data : elaborate);
    return *this;
  }

  Phrase Draft::getType() {
    return phrase.getType();
  }

  bool Draft::containsAction() {
    return phrase.containsAction();
  }

  Draft &Draft::setAction(Action action) {
    if (!containsAction()) {
      phrase.cached.contains |= phrase::Contains::ACTION;
      phrase.meta.size += sizeof(Phrase::ActionBinding);
    }

    phrase.setAction(action);
    return *this;
  }

  Draft &Draft::setActionImplementation(Phrase implementation) {
    if (!containsAction()) THROW(, "Draft doesnt contain action, so its implementation cannot be set.")
    phrase.setActionImplementation(implementation);
    return *this;
  }

  Draft::Action Draft::getAction() {
    return phrase.getAction();
  }

  bool Draft::containsSuccessor() {
    return phrase.containsSuccessor();
  }

  Draft &Draft::setSuccessor(Phrase successor) {
    if (!containsSuccessor()) {
      phrase.cached.contains |= phrase::Contains::SUCCESSOR;
      phrase.meta.size += sizeof(Size);
    }

    phrase.setSuccessor(successor);

    return *this;
  }

  Phrase Draft::getSuccessor() {
    return phrase.getSuccessor();
  }

  Phrase &Draft::save() {
    Phrase pushed = push();
    Size addr = pushed.getAddress();
    phrase.setAddress(addr);

    phrase.allocate(phrase.meta.size);

    return phrase.save(true).load();
  }
} // namespace lexicon

#endif
