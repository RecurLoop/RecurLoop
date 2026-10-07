#include <recurloop/NativeCall.hpp>
#include <recurloop/ProcessControl.hpp>
#include <context/Context.hpp>
#include <compiler/DynamicLinker.hpp>
#include <compiler/Module.hpp>
#include <utilities/Exception.hpp>
#include <cstring>
#include <string_view>
#include <vector>

#if defined(__x86_64__)
extern "C" std::uintptr_t recurloop_call_scalar_native_sysv(std::uintptr_t entry, const std::uintptr_t *args,
                                                              std::size_t count);
asm(R"(
  .text
  .global recurloop_call_scalar_native_sysv
  .type recurloop_call_scalar_native_sysv, @function
recurloop_call_scalar_native_sysv:
  push %rbp
  mov %rsp, %rbp
  mov %rdi, %r11
  mov %rsi, %r10
  mov %rdx, %rax

  cmp $6, %rax
  jbe .Lrecurloop_scalar_registers

  mov %rax, %rcx
  sub $6, %rcx
  lea 0(,%rcx,8), %r8
  add $15, %r8
  and $-16, %r8
  sub %r8, %rsp

  xor %edx, %edx
.Lrecurloop_scalar_stack:
  cmp %rcx, %rdx
  jae .Lrecurloop_scalar_registers
  mov 48(%r10,%rdx,8), %r8
  mov %r8, (%rsp,%rdx,8)
  inc %rdx
  jmp .Lrecurloop_scalar_stack

.Lrecurloop_scalar_registers:
  test %rax, %rax
  je .Lrecurloop_scalar_call
  mov 0(%r10), %rdi
  cmp $1, %rax
  je .Lrecurloop_scalar_call
  mov 8(%r10), %rsi
  cmp $2, %rax
  je .Lrecurloop_scalar_call
  mov 16(%r10), %rdx
  cmp $3, %rax
  je .Lrecurloop_scalar_call
  mov 24(%r10), %rcx
  cmp $4, %rax
  je .Lrecurloop_scalar_call
  mov 32(%r10), %r8
  cmp $5, %rax
  je .Lrecurloop_scalar_call
  mov 40(%r10), %r9

.Lrecurloop_scalar_call:
  xor %eax, %eax
  call *%r11
  mov %rbp, %rsp
  pop %rbp
  ret
  .size recurloop_call_scalar_native_sysv, .-recurloop_call_scalar_native_sysv
)");
#endif

namespace recurloop {
  namespace {
    thread_local context::Context *activeContext = nullptr;

    void nativeError(std::uint32_t code) noexcept {
      if (!activeContext) {
        constexpr std::string_view message = "recurloop: native integer arithmetic error\n";
        (void)::write(STDERR_FILENO, message.data(), message.size());
        _exit(1);
      }
      if (activeContext->exec.pendingException) return;
      try {
        if (code == 1) THROW(, "integer division by zero")
        THROW(, "integer division overflow")
      } catch (...) {
        activeContext->exec.pendingException = std::current_exception();
      }
    }

    std::uint32_t nativePending() noexcept {
      if (!activeContext) return 0;
      if (!activeContext->exec.pendingException && ProcessControl::interrupted()) {
        try { throw SourceException(__FILE__, __LINE__, __PRETTY_FUNCTION__,
            {activeContext->source.path, activeContext->source.line, activeContext->source.position}, "request cancelled", 130); }
        catch (...) { activeContext->exec.pendingException = std::current_exception(); }
      }
      return activeContext->exec.pendingException ? 1 : 0;
    }
  }

  NativeExecution::NativeExecution(context::Context &context) noexcept : previous(activeContext) { activeContext = &context; }
  NativeExecution::~NativeExecution() { activeContext = previous; }

  void NativeExecution::install() {
    auto &linker = compiler::DynamicLinker::instance();
    linker.registerSymbol(NativeErrorSymbol, reinterpret_cast<std::uintptr_t>(nativeError));
    linker.registerSymbol(NativePendingSymbol, reinterpret_cast<std::uintptr_t>(nativePending));
  }

  void NativeExecution::addDefaults(compiler::Module &module) {
    // Standalone ELF output has the same checks without depending on the host.
    // Weak definitions are replaced by the request-local implementations in JIT.
    if (module.findSymbol(NativePendingSymbol) == nullptr) {
      const std::uint8_t code[] = {0xf3, 0x0f, 0x1e, 0xfa, 0x31, 0xc0, 0xc3};
      const auto offset = module.append(compiler::SectionKind::Text, code, 16);
      module.define(NativePendingSymbol, compiler::SectionKind::Text, offset, compiler::SymbolBinding::Weak);
    }
    if (module.findSymbol(NativeErrorSymbol) != nullptr) return;
    constexpr std::string_view message = "recurloop: native integer arithmetic error\n";
    const std::string messageSymbol = module.symbols().front().name + ".native.error.message";
    const auto text = module.append(compiler::SectionKind::ReadOnlyData,
        std::span(reinterpret_cast<const std::uint8_t *>(message.data()), message.size()), 1);
    module.define(messageSymbol, compiler::SectionKind::ReadOnlyData, text, compiler::SymbolBinding::Local);
    std::vector<std::uint8_t> code = {
      0xf3, 0x0f, 0x1e, 0xfa, 0x55, 0x48, 0x89, 0xe5, // endbr64; push rbp; mov rbp,rsp
      0xbf, 2, 0, 0, 0,                               // mov edi,2
      0x48, 0x8d, 0x35, 0, 0, 0, 0,                   // lea rsi,[rip+message]
      0xba, 0, 0, 0, 0,                              // mov edx,length
      0xe8, 0, 0, 0, 0,                              // call write
      0xbf, 1, 0, 0, 0,                              // mov edi,1
      0xe8, 0, 0, 0, 0,                              // call _exit
      0x0f, 0x0b                                     // ud2
    };
    const std::uint32_t length = message.size();
    std::memcpy(code.data() + 21, &length, sizeof(length));
    const auto offset = module.append(compiler::SectionKind::Text, code, 16);
    module.define(NativeErrorSymbol, compiler::SectionKind::Text, offset, compiler::SymbolBinding::Weak);
    for (const auto *name : {"write", "_exit"}) if (!module.findSymbol(name)) module.import(name);
    module.relocate(compiler::SectionKind::Text, offset + 16, compiler::RelocationKind::PCRelative32,
                    messageSymbol, -4);
    module.relocate(compiler::SectionKind::Text, offset + 26, compiler::RelocationKind::PLTRelative32, "write", -4);
    module.relocate(compiler::SectionKind::Text, offset + 36, compiler::RelocationKind::PLTRelative32, "_exit", -4);
  }

  bool scalarNativeSysvAvailable() noexcept {
#if defined(__x86_64__)
    return true;
#else
    return false;
#endif
  }

  std::uintptr_t callScalarNativeSysv(std::uintptr_t entry, const std::uintptr_t *args, std::size_t count) noexcept {
#if defined(__x86_64__)
    return recurloop_call_scalar_native_sysv(entry, args, count);
#else
    (void)entry;
    (void)args;
    (void)count;
    return 0;
#endif
  }
} // namespace recurloop
