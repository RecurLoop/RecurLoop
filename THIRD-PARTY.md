# Third-party components in binary releases

RecurLoop is Apache-2.0 licensed. Production binaries also contain statically
linked LLVM 22.1.8 components under Apache-2.0 WITH LLVM-exception. The LLVM
license is installed under `share/doc/RecurLoop/third-party/llvm/`; the exact
upstream binary distribution used for official releases is identified by URL
and SHA-256 in `share/recurloop/RELEASE-METADATA.txt`.

RecurLoop does **not** redistribute Clang, LLD, a libc sysroot, or LLVM source.
`emit object` uses the linked LLVM backend plus host LLD for the final relocatable link.
`emit executable` uses compatible host Clang/LLD when present on `PATH` (Debian/Ubuntu packages:
`clang-22` and `lld-22`).

Linux release builds currently link the C++/GCC runtime statically where the
host toolchain supports it; those runtime pieces are covered by the GCC Runtime
Library Exception. The produced RecurLoop executable dynamically uses the
platform libc and may use explicitly audited LLVM support dependencies such as
zlib/zstd/terminfo/XML from the target distribution. No glibc development
objects or linker sysroot are redistributed by the RecurLoop archive.

Official LLVM release: https://github.com/llvm/llvm-project/releases/tag/llvmorg-22.1.8
GCC Runtime Library Exception: https://www.gnu.org/licenses/gcc-exception-3.1.html
