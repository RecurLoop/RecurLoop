#include <recurloop/NativeCall.hpp>

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
