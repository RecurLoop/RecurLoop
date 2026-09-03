#pragma once

#include <compiler/Module.hpp>
#include <utilities/JitMemory.hpp>

#include <cstddef>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace compiler {
  class JitImage {
  public:
    std::uintptr_t address(std::string_view symbol) const;
    std::size_t offset() const;
    std::size_t size() const;

  private:
    struct ResolvedSymbol {
      std::string name;
      std::uintptr_t address = 0;
    };

    std::size_t imageOffset = 0;
    std::size_t imageSize = 0;
    std::vector<ResolvedSymbol> resolvedSymbols;

    friend class JitLinker;
  };

  class JitLinker {
  public:
    using Resolver = std::function<std::optional<std::uintptr_t>(std::string_view)>;

    static JitImage link(const Module &module, JitMemory &memory, const Resolver &resolver = {});
  };
} // namespace compiler
