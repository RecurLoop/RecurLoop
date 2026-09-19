.DEFAULT_GOAL := build

RECURLOOP := build/Release/bin/recurloop

EXAMPLE ?=
ARGS ?= --file program.rl.example
BUNDLE ?= recurloop-work.zip
PREFIX ?=

RELEASE_BUILD_FILE := build/Release/build.ninja

.PHONY: help build release check test verify libraries install run list-examples example examples bundle benchmark reconfigure clean

help:
	@echo 'RecurLoop'
	@echo
	@echo 'Build:'
	@echo '  make              Build RecurLoop'
	@echo '  make release      Build release with pinned dependencies'
	@echo '  make libraries    Build .rli libraries'
	@echo '  make clean        Remove build directories'
	@echo
	@echo 'Test:'
	@echo '  make check        Run affected tests and examples'
	@echo '  make test         Run all tests'
	@echo '  make verify       Run full release verification'
	@echo
	@echo 'Use:'
	@echo '  make run          Run RecurLoop'
	@echo '  make examples     Run all examples'
	@echo '  make example EXAMPLE=<name>'
	@echo '  make list-examples'
	@echo
	@echo 'Install:'
	@echo '  sudo make install'
	@echo '  make install PREFIX=$$HOME/.local'
	@echo
	@echo 'Other:'
	@echo '  make reconfigure  Reconfigure the Release build'
	@echo '  make bundle       Create a source bundle'
	@echo '  make benchmark    Build benchmarks'

$(RELEASE_BUILD_FILE): Makefile CMakePresets.json cmake/Configure.cmake
	@echo '[configure] Release'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=AUTO -P cmake/Configure.cmake

reconfigure:
	@echo '[configure] Release'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=AUTO -P cmake/Configure.cmake

build: $(RELEASE_BUILD_FILE)
	@echo '[build] RecurLoop'
	@cmake --build --preset release --target Recurloop
	@echo '[build] ready: $(RECURLOOP)'

release:
	@echo '[release] configure'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=PINNED -P cmake/Configure.cmake
	@echo '[release] build'
	@cmake --build --preset release --target Recurloop RecurloopLibraries
	@echo '[release] ready'

check: $(RELEASE_BUILD_FILE)
	@echo '[check] run'
	@cmake --build --preset release --target RecurloopCheck
	@echo '[check] passed'

test: $(RELEASE_BUILD_FILE)
	@echo '[test] build'
	@cmake --build --preset release --target Recurloop RecurloopUnitTests
	@echo '[test] unit'
	@ctest --test-dir build/Release -L unit --output-on-failure --parallel
	@echo '[test] feature'
	@ctest --test-dir build/Release -L feature --output-on-failure
	@echo '[test] passed'

libraries: $(RELEASE_BUILD_FILE)
	@echo '[libraries] build'
	@cmake --build --preset release --target RecurloopLibraries
	@echo '[libraries] ready'

verify:
	@echo '[verify] configure'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=PINNED -P cmake/Configure.cmake
	@echo '[verify] build'
	@cmake --build --preset release --target Recurloop RecurloopUnitTests
	@echo '[verify] unit'
	@ctest --test-dir build/Release -L unit --output-on-failure --parallel
	@echo '[verify] feature'
	@ctest --test-dir build/Release -L feature --output-on-failure
	@echo '[verify] libraries + core'
	@cmake --build --preset release --target RecurloopLibraries RecurloopCoreVerify
	@echo '[verify] examples'
	@tools/examples.sh all "$(abspath $(RECURLOOP))"
	@echo '[verify] core workflow'
	@libraries/recurloop/test-core.sh "$(abspath $(RECURLOOP))"
	@echo '[verify] passed'

install:
	@echo '[install] configure'
	@cmake -DPRESET=release -DTOOLCHAIN_MODE=PINNED $(if $(PREFIX),-DINSTALL_PREFIX="$(PREFIX)") -P cmake/Configure.cmake
	@echo '[install] build'
	@cmake --build --preset release --target Recurloop RecurloopLibraries
	@echo '[install] install'
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
	@echo '[clean] build directories'
	@cmake -E rm -rf build/Release build/Debug build/Benchmark build/Check build/Verify
