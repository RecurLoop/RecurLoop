#pragma once

#include "_module_classes.hpp"
#include "Phrase.hpp"
#include "Dictionary.hpp"
#include <utilities/Declaration.hpp>

namespace lexicon {
  class Draft : public Dictionary {
  public:
    using Action = Phrase::Action;

  public:
    DECLARATION Draft();
    DECLARATION Draft(Dictionary dictionary);
    DECLARATION Draft(Dictionary dictionary, Action action);
    DECLARATION Draft(Dictionary dictionary, Phrase prototype);
    DECLARATION Draft(Dictionary dictionary, Phrase phrase, Action action);
    DECLARATION Draft(Dictionary dictionary, Phrase phrase, Phrase prototype);
    DECLARATION Draft(Draft &draft);

    DECLARATION Draft &append(Byte key, Size keyOffset, Size keyBits);

    DECLARATION bool containsSubdictionary();
    DECLARATION Draft &enableSubdictionary();

    DECLARATION bool containsParent();
    DECLARATION Draft &setParent(Phrase parent);
    DECLARATION Phrase getParent();

    DECLARATION bool containsPrototype();
    DECLARATION Draft &setPrototype(Phrase prototype);
    DECLARATION Phrase getPrototype();

    DECLARATION bool containsType();
    DECLARATION Draft &setType(Phrase type);
    DECLARATION Draft &setDefaultType(Phrase data, Phrase elaborate);
    DECLARATION Phrase getType();

    DECLARATION bool containsAction();
    DECLARATION Draft &setAction(Action action);
    DECLARATION Draft &setActionImplementation(Phrase implementation);
    DECLARATION Action getAction();

    DECLARATION bool containsSuccessor();
    DECLARATION Draft &setSuccessor(Phrase successor);
    DECLARATION Phrase getSuccessor();

    DECLARATION Phrase &save();

  public:
    template <Size N> DECLARATION Draft &append(const char (&str)[N]);

  protected:
    Phrase phrase = {};
  };

  template <Size N> Draft &Draft::append(const char (&str)[N]) {
    return append(Byte((unsigned char *)str), 0, (N - 1) * Byte::length);
  }
} // namespace lexicon
