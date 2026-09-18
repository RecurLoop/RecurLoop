.DEFAULT_GOAL := build

RECURLOOP := build/Release/bin/recurloop
EXAMPLE ?=
ARGS ?= --file program.rl.example
BUNDLE ?= recurloop-work.zip
PREFIX ?=

RELEASE_BUILD_FILE := build/Release/build.ninja

.PHONY: help build release check test verify libraries install run list-examples example examples bundle benchmark reconfigure clean

help:
	@echo 'RecurLoop commands'
	@echo
	@echo '  make                 Build Release + LLVM; prefer cached pinned, else compatible system LLVM'
	@echo '  make release         Build Release with the exact pinned LLVM/zlib/zstd toolchain'
	@echo '  make check           Incremental unit + feature + example checks from the CMake/Ninja graph'
	@echo '  make test            Full unit + feature tests on build/Release using AUTO selection'
	@echo '  make verify          Full verification using the exact pinned release toolchain'
	@echo '  make libraries       Build distributable .rli libraries with build/Release'
	@echo '  make install         Install a pinned-toolchain release + compiled libraries'
	@echo '  make run [ARGS=...]  Build and run the Release binary'
	@echo '  make examples        Run examples with the Release binary'
	@echo '  make bundle          Create a compact source bundle'
	@echo '  make reconfigure     Re-run Release AUTO configuration explicitly'
	@echo
	@echo 'AUTO prefers an already prepared pinned LLVM 22.1.6/toolchain cache; otherwise'
	@echo 'it uses a compatible system LLVM 22.x. make release/verify'
	@echo 'always require the pinned versions and prepare them once when missing.'
	@echo
	@echo 'All normal Make targets share one build tree: build/Release.'
	@echo 'Debug is separate and intentionally owned by VS Code/CMake Tools (preset: debug).'
	@echo
	@echo 'Installation examples:'
	@echo '  sudo make install'
	@echo '  make install PREFIX=$$HOME/.local'
	@echo '  make install PREFIX=/usr DESTDIR=/tmp/recurloop-package'

$(RELEASE_BUILD_FILE): Makefile CMakePresets.json cmake/Configure.cmake
	@echo '[configure] Release + LLVM (AUTO toolchain)'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=AUTO -P cmake/Configure.cmake

reconfigure:
	@echo '[configure] force Release + LLVM (AUTO toolchain)'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=AUTO -P cmake/Configure.cmake

build: $(RELEASE_BUILD_FILE)
	@echo '[build] build recurloop'
	@cmake --build --preset release --target Recurloop
	@echo '[build] ready: $(RECURLOOP)'

release:
	@echo '[release] configure exact pinned LLVM toolchain'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=PINNED -P cmake/Configure.cmake
	@echo '[release] build recurloop'
	@cmake --build --preset release --target Recurloop
	@echo '[release] ready: $(RECURLOOP)'

check: $(RELEASE_BUILD_FILE)
	@echo '[check] build and run affected unit, feature, and example checks'
	@cmake --build --preset release --target RecurloopCheck
	@echo '[check] passed'

test: $(RELEASE_BUILD_FILE)
	@echo '[test] build unit tests'
	@cmake --build --preset release --target Recurloop RecurloopUnitTests
	@echo '[test] unit'
	@ctest --test-dir build/Release -L unit --output-on-failure --parallel
	@echo '[test] feature'
	@ctest --test-dir build/Release -L feature --output-on-failure
	@echo '[test] passed'

libraries: $(RELEASE_BUILD_FILE)
	@echo '[libraries] build compiled libraries'
	@cmake --build --preset release --target RecurloopLibraries
	@echo '[libraries] ready: build/Release/libraries'

verify:
	@echo '[verify] configure exact pinned release toolchain'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=PINNED -P cmake/Configure.cmake
	@echo '[verify] build unit tests'
	@cmake --build --preset release --target Recurloop RecurloopUnitTests
	@echo '[verify] unit'
	@ctest --test-dir build/Release -L unit --output-on-failure --parallel
	@echo '[verify] feature'
	@ctest --test-dir build/Release -L feature --output-on-failure
	@echo '[verify] build libraries + core fixed-point verification'
	@cmake --build --preset release --target RecurloopLibraries RecurloopCoreVerify
	@echo '[verify] examples'
	@tools/examples.sh all "$(abspath $(RECURLOOP))"
	@echo '[verify] core workflow'
	@libraries/recurloop/test-core.sh "$(abspath $(RECURLOOP))"
	@echo '[verify] passed'

install:
	@echo '[install] configure exact pinned release toolchain'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=PINNED $(if $(PREFIX),-DINSTALL_PREFIX="$(PREFIX)") -P cmake/Configure.cmake
	@echo '[install] build recurloop + libraries'
	@cmake --build --preset release --target Recurloop RecurloopLibraries
	@echo '[install] install$(if $(PREFIX), to $(PREFIX),)'
	@DESTDIR="$(DESTDIR)" cmake --install build/Release $(if $(PREFIX),--prefix "$(PREFIX)")
	@echo '[install] done'

run: build
	@"$(RECURLOOP)" $(ARGS)

list-examples:
	@tools/examples.sh list

example: build
	@test -n "$(EXAMPLE)" || { echo 'usage: make example EXAMPLE=01-getting-started/hello-world' >&2; exit 2; }
	@tools/examples.sh run "$(abspath $(RECURLOOP))" "$(EXAMPLE)"

examples: build
	@tools/examples.sh all "$(abspath $(RECURLOOP))"

bundle:
	@echo '[bundle] create $(BUNDLE)'
	@cmake -DOUTPUT="$(BUNDLE)" -P cmake/Bundle.cmake
	@echo '[bundle] ready: $(BUNDLE)'

benchmark:
	@echo '[benchmark] configure'
	@cmake --preset benchmark
	@echo '[benchmark] build'
	@cmake --build --preset benchmark --target RecurloopBenchmarks

clean:
	@echo '[clean] remove local build trees (keep shared dependency/toolchain cache)'
	@cmake -E rm -rf build/Release build/Debug build/Benchmark build/Check build/Verify
