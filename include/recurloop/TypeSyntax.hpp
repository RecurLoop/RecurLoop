#pragma once

#include <compiler/TypeSystem.hpp>

#include <cstddef>
#include <string>
#include <string_view>

namespace context {
  class Context;
}

namespace recurloop {
  class TypeSyntax {
  public:
    class Cursor {
    public:
      virtual ~Cursor() = default;
      virtual std::string_view typeCurrent() const = 0;
      virtual bool typeAccept(std::string_view token) = 0;
      virtual void typeExpect(std::string_view token) = 0;
      virtual bool typeSkipLayout() {
        return false;
      }
      virtual std::string typeIdentifier(std::string_view description) = 0;
      virtual std::size_t typeNumber(std::string_view description) = 0;
      [[noreturn]] virtual void typeError(const std::string &message) = 0;
    };

    TypeSyntax() = delete;

    static void setup(context::Context &context);
    static compiler::TypeId parse(context::Context &context, Cursor &cursor, std::string scope = {});
  };
} // namespace recurloop
