# Production releases

## Dependency model

RecurLoop never builds LLVM as part of its normal build or release pipeline.
LLVM is selected by one variable:

```text
RECURLOOP_LLVM_PROVIDER=AUTO|SYSTEM|ARCHIVE
```

- `AUTO` (development default): use the exact pinned LLVM 22.1.8 archive when
  it is already cached; otherwise use a compatible installed LLVM 22.x; if
  neither is available, download and cache the pinned official archive.
- `SYSTEM`: require an installed LLVM 22.x. On Debian/Ubuntu the intended setup
  is `apt install llvm-22 llvm-22-dev clang-22 lld-22`.
- `ARCHIVE`: use only the official LLVM 22.1.8 binary release pinned by exact
  URL and SHA-256 in `cmake/LLVMDistribution.cmake`. This is the production
  provider.

The archive is cached below `.cache/deps/llvm/<version>/<platform>/`. Switching
between `native` and `all` does not create or build another LLVM SDK; it changes
only which already-built LLVM components are linked into RecurLoop:

```text
RECURLOOP_LLVM_LINK_TARGETS=native   # default and production
RECURLOOP_LLVM_LINK_TARGETS=all      # explicit development opt-in
```

`make llvm` only downloads, verifies and extracts the immutable upstream
archive. It does not compile LLVM.

## Development

Normal optimized development uses:

```sh
make build
make check
```

On a fresh checkout with a distro LLVM 22 installation these commands use the
system SDK without downloading anything. Once the pinned archive exists in the
dependency cache, `AUTO` intentionally prefers it. A strict system-only
configuration is:

```sh
cmake --preset release -DRECURLOOP_LLVM_PROVIDER=SYSTEM
```

A deterministic archive-backed configuration is:

```sh
cmake --preset release -DRECURLOOP_LLVM_PROVIDER=ARCHIVE
```

The LLVM backend itself is linked into `recurloop`. The JIT/runtime backend is in-process. Object emission uses host `ld.lld`;
executable emission delegates the final system link to compatible `clang`/`ld.lld` on `PATH`; this keeps libc/sysroot ownership with
the target operating system instead of embedding a Linux-specific SDK in the
RecurLoop package.

## Linux release profile

The current published binary profile is explicit:

- Linux x86-64;
- glibc >= 2.35;
- generic x86-64 CPU baseline;
- LLVM 22.1.8 official Linux X64 binary distribution, SHA-256 pinned;
- native LLVM backend linked statically into RecurLoop;
- Clang/LLD are build/optional executable-link dependencies, not package files.

The archive contains:

```text
bin/recurloop
share/recurloop/libraries/{language-kit,shell,inferred,http,gui,ide,project,embed}.rli
share/recurloop/BUILD-COMPATIBILITY.txt
share/recurloop/RELEASE-METADATA.txt
share/recurloop/PACKAGE-MANIFEST.sha256
share/doc/RecurLoop/...
```

Musl/Alpine is intentionally a separate build profile. A musl container should
normally install its own LLVM development package and configure
`RECURLOOP_LLVM_PROVIDER=SYSTEM`; the glibc official LLVM archive must not be
silently reused there. Windows, macOS/iOS and embedded targets follow the same
provider interface but require their own host ABI/package profiles.

## Verification and determinism

```sh
make verify
make package
```

Production packaging requires `ARCHIVE`, native-only LLVM linking and the
release ABI profile. The package is staged, audited, smoke-tested, hashed and
created with stable ordering, ownership, permissions and timestamps derived
from `SOURCE_DATE_EPOCH`. Official release automation packages the same build
twice and rejects it if the two archive SHA-256 values differ.

Installed-package verification checks every standard `.rli`, package integrity,
relocation through a symlink, normal runtime behavior and LLVM object emission.
It also clears `PATH` and confirms that `emit executable` gives a useful
Clang/LLD installation error rather than falling back to an absolute build
machine path.

The ELF audit rejects unexpected architectures, interpreters, RPATH/RUNPATH and
undeclared shared dependencies and computes the actual maximum GLIBC symbol
version. Official CI uses a Linux x86-64 glibc 2.35 profile and runs the finished
archive in clean representative newer distributions with networking disabled.

## Docker and other libc profiles

The provider model is independent of the build container:

```text
Docker glibc + ARCHIVE  -> deterministic official Linux release
Docker glibc + SYSTEM   -> distro-native developer/package build
Docker musl  + SYSTEM   -> future musl release profile
```

A container/profile owns its libc, headers and final executable-linking tools;
RecurLoop owns only the LLVM backend it links. This avoids a hidden copied
sysroot and keeps future platform ports explicit.
