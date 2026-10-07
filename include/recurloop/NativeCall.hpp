#pragma once

#include <cstddef>
#include <cstdint>

namespace context {
  class Context;
}
namespace compiler {
  class Module;
}

namespace recurloop {
  // Generated frames report faults and return normally. Only a host boundary
  // may rethrow the request's pending exception.
  class NativeExecution {
  public:
    explicit NativeExecution(context::Context &context) noexcept;
    ~NativeExecution();
    NativeExecution(const NativeExecution &) = delete;
    NativeExecution &operator=(const NativeExecution &) = delete;
    static void install();
    static void addDefaults(compiler::Module &module);

  private:
    context::Context *previous;
  };
  inline constexpr const char *NativeErrorSymbol = "recurloop_native_error";
  inline constexpr const char *NativePendingSymbol = "recurloop_native_pending";
  bool scalarNativeSysvAvailable() noexcept;
  std::uintptr_t callScalarNativeSysv(std::uintptr_t entry, const std::uintptr_t *args, std::size_t count) noexcept;
} // namespace recurloop
