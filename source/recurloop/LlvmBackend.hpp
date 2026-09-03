#pragma once

#include "FunctionsInternal.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace recurloop::function_internal {
  struct LlvmProgram {
    std::vector<std::vector<std::uint8_t>> objects;
    std::vector<std::string> providedSymbols;
    std::vector<std::string> imports;
    std::string triple;
  };

  struct LlvmRuntimeImport {
    std::string name;
    std::uintptr_t address = 0;
  };

  struct LlvmPhraseCall {
    std::string symbol;
    std::optional<compiler::TypedFunction> function;
    std::vector<compiler::TypedValue> arguments;
    std::uintptr_t directEntry = 0;
    std::uintptr_t trampoline = 0;
    std::size_t phraseAddress = 0;
    std::size_t line = 1;
    std::size_t column = 1;
    bool nativeAbi = false;
  };

  struct LlvmPhraseModule {
    compiler::Module module;
    std::vector<LlvmRuntimeImport> imports;
  };

  LlvmProgram generateLlvmProgram(context::Context &context, const FunctionDefinition &signature,
                                  const std::vector<Statement> &body, std::string_view executableEntry);
  compiler::Module generateLlvmModule(context::Context &context, const FunctionDefinition &signature,
                                      const std::vector<Statement> &body);
  LlvmPhraseModule generateLlvmPhraseModule(context::Context &context, std::string_view symbol,
                                            std::span<const LlvmPhraseCall> calls);
} // namespace recurloop::function_internal
