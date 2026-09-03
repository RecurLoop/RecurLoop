#pragma once

#include "_module_classes.hpp"
#include <utilities/Declaration.hpp>

namespace context {
  class Config {
  public:
    struct Source {
      struct Buffer {
        Size size = 0;
      } buffer;
    } source;

    struct Memory {
      Size size = 0;
    };

    struct Lexicon {
      struct Memory memory;
    } lexicon;

    struct Runtime {
      struct Memory memory;
    } runtime;

    struct Workspace {
      struct Key {
        struct Memory memory;
      } key;

      struct Code {
        struct Memory memory;
      } code;
    } workspace;

    struct Exception {
      bool continues = false;
    } exception;
  };
} // namespace context
