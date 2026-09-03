SHELL := /bin/bash

.DEFAULT_GOAL := help

BUILD_TYPE ?= Debug
BUILD_ROOT ?= build
CONFIG_DIR ?= $(BUILD_ROOT)/$(BUILD_TYPE)
DEPS_DIR ?= $(BUILD_ROOT)/_deps
ENABLE_TESTS ?= ON
ENABLE_LLVM ?= OFF

RECURLOOP := $(CONFIG_DIR)/bin/recurloop

CLANG ?= $(shell command -v clang)
CLANGXX ?= $(shell command -v clang++)

EXAMPLE ?=
ARGS ?= --file program.rl.example


.PHONY: \
	help \
	configure \
	build \
	release \
	run \
	showcase \
	list-examples \
	example \
	examples \
	test \
	unit \
	feature \
	clean


help:
	@echo 'RecurLoop developer commands'
	@echo
	@echo '  make build                         Configure and build (Debug by default)'
	@echo '  make release                       Build Release with LLVM in build/Release/'
	@echo '  make run                           Run program.rl.example'
	@echo '  make run ARGS='\''--file path/to/program.rl'\'''
	@echo '  make run ARGS='\''--string "print 42"'\'''
	@echo '  make list-examples                 List example names'
	@echo '  make example EXAMPLE=01-getting-started/hello-world'
	@echo '  make examples                      Validate every example and workflow'
	@echo '  make test | unit | feature         Run tests'
	@echo '  make showcase                      Run the complete language tour'
	@echo
	@echo 'Debug is the default build type for build, run, examples, and tests.'
	@echo 'To use Release with LLVM:'
	@echo '  make release'
	@echo '  make run BUILD_TYPE=Release ARGS='\''--file path/to/program.rl'\'''
	@echo '  make test BUILD_TYPE=Release'
	@echo '  make examples BUILD_TYPE=Release'
	@echo
	@echo 'Normal run/example/test commands only build when recurloop is missing.'
	@echo
	@echo 'Overrides:'
	@echo '  BUILD_TYPE=Release'
	@echo '  BUILD_ROOT=build-custom'
	@echo '  ENABLE_TESTS=OFF'
	@echo '  ENABLE_LLVM=ON'


# ---------------------------------------------------------------------------
# Configuration / build
# ---------------------------------------------------------------------------

configure:
	cmake -S . -B "$(CONFIG_DIR)" -G Ninja \
		-DCMAKE_BUILD_TYPE="$(BUILD_TYPE)" \
		-DCMAKE_C_COMPILER="$(CLANG)" \
		-DCMAKE_CXX_COMPILER="$(CLANGXX)" \
		-DCMAKE_EXE_LINKER_FLAGS=-fuse-ld=lld \
		-DCMAKE_SHARED_LINKER_FLAGS=-fuse-ld=lld \
		-DCMAKE_MODULE_LINKER_FLAGS=-fuse-ld=lld \
		-DENABLE_TESTS="$(ENABLE_TESTS)" \
		-DRECURLOOP_ENABLE_LLVM="$(ENABLE_LLVM)" \
		-DFETCHCONTENT_BASE_DIR="$(abspath $(DEPS_DIR))"
	cmake -E copy_if_different \
		"$(CONFIG_DIR)/compile_commands.json" \
		"$(BUILD_ROOT)/compile_commands.json"


build: configure
	cmake --build "$(CONFIG_DIR)" --parallel --target all


release:
	$(MAKE) build \
		BUILD_TYPE=Release \
		ENABLE_TESTS="$(ENABLE_TESTS)" \
		ENABLE_LLVM=ON


# This is intentionally a real filesystem target, not .PHONY.
#
# Commands which only need recurloop depend on this target.
# If the executable already exists, Make does nothing.
# If it does not exist, a normal build is performed.
$(RECURLOOP):
	@echo 'recurloop executable not found; building it first...'
	@$(MAKE) build \
		BUILD_TYPE="$(BUILD_TYPE)" \
		BUILD_ROOT="$(BUILD_ROOT)" \
		ENABLE_TESTS="$(ENABLE_TESTS)" \
		ENABLE_LLVM="$(ENABLE_LLVM)"


# ---------------------------------------------------------------------------
# Running programs
# ---------------------------------------------------------------------------

run: $(RECURLOOP)
	"$(RECURLOOP)" $(ARGS)


showcase: $(RECURLOOP)
	"$(RECURLOOP)" --file program.rl.example


# ---------------------------------------------------------------------------
# Examples
# ---------------------------------------------------------------------------

list-examples:
	@find examples -name main.rl -printf '%h\n' \
		| sed 's|^examples/||' \
		| sort
	@printf '%s\n' \
		'07-workflows/reusable-language-image' \
		'07-workflows/reusable-syntax-image' \
		'07-workflows/shell-language' \
		'07-workflows/amber-language' \
		'07-workflows/prolog-language' \
		'07-workflows/haskell-language' \
		'07-workflows/erlang-language' \
		'07-workflows/source-debugger'


example: $(RECURLOOP)
	@test -n "$(EXAMPLE)" || { \
		echo 'usage: make example EXAMPLE=01-getting-started/hello-world' >&2; \
		exit 2; \
	}

	@if test -f "examples/$(EXAMPLE)/main.rl"; then \
		"$(RECURLOOP)" --file "examples/$(EXAMPLE)/main.rl"; \
	else \
		case "$(EXAMPLE)" in \
		07-workflows/reusable-language-image) \
			"$(RECURLOOP)" \
				--file examples/07-workflows/reusable-language-image/build.rl && \
			"$(RECURLOOP)" \
				--import /tmp/recurloop-phrase-language.rli \
				--file examples/07-workflows/reusable-language-image/use.rl \
			;; \
		07-workflows/reusable-syntax-image) \
			"$(RECURLOOP)" \
				--file examples/07-workflows/reusable-syntax-image/build.rl && \
			"$(RECURLOOP)" \
				--import /tmp/recurloop-phrase-syntax.rli \
				--file examples/07-workflows/reusable-syntax-image/use.rl \
			;; \
		07-workflows/shell-language) \
			"$(RECURLOOP)" \
				--file examples/07-workflows/shell-language/library.rl && \
			for file in top_level.rl pipeline.rl functions.rl example.rl; do \
				"$(RECURLOOP)" \
					--import /tmp/recurloop-shell-library.rli \
					--file "examples/07-workflows/shell-language/$$file" \
					|| exit; \
			done \
			;; \
		07-workflows/amber-language) \
			"examples/07-workflows/amber-language/run-tests.sh" "$(abspath $(RECURLOOP))" \
			;; \
		07-workflows/prolog-language) \
			"examples/07-workflows/prolog-language/run-tests.sh" "$(abspath $(RECURLOOP))" \
			;; \
		07-workflows/haskell-language) \
			"examples/07-workflows/haskell-language/run-tests.sh" "$(abspath $(RECURLOOP))" \
			;; \
		07-workflows/erlang-language) \
			"examples/07-workflows/erlang-language/run-tests.sh" "$(abspath $(RECURLOOP))" \
			;; \
		07-workflows/source-debugger) \
			"$(RECURLOOP)" \
				--file examples/07-workflows/source-debugger/debugger.rl \
			;; \
		*) \
			echo "unknown example: $(EXAMPLE)" >&2; \
			exit 2 \
			;; \
		esac; \
	fi


# Keep successful low-level examples quiet, but always show which case is
# running and replay captured stdout/stderr if a case fails.
#
# Workflow regression runners are intentionally NOT redirected to /dev/null:
# they already emit concise "[language] ... ok" status lines and useful
# diagnostics/diffs on failure.
examples: $(RECURLOOP)
	@set -euo pipefail; \
	run_quiet() { \
		local label="$$1"; \
		shift; \
		local output; \
		output="$$(mktemp)"; \
		printf '%s\n' "$$label"; \
		if "$$@" >"$$output" 2>&1; then \
			rm -f "$$output"; \
		else \
			local status=$$?; \
			printf '\nFAILED: %s (exit %d)\n' "$$label" "$$status" >&2; \
			printf '%s\n' '----- captured output -----' >&2; \
			cat "$$output" >&2; \
			printf '%s\n\n' '---------------------------' >&2; \
			rm -f "$$output"; \
			exit "$$status"; \
		fi; \
	}; \
	\
	mapfile -t files < <(find examples -name main.rl -print | sort); \
	printf '== Core examples (%d) ==\n' "$${#files[@]}"; \
	for i in "$${!files[@]}"; do \
		run_quiet \
			"$$(printf '[%02d/%02d] %s' "$$((i + 1))" "$${#files[@]}" "$${files[$$i]}")" \
			"$(RECURLOOP)" --file "$${files[$$i]}"; \
	done; \
	\
	echo; \
	echo '== Reusable language image =='; \
	run_quiet \
		'[workflow] reusable-language-image: build' \
		"$(RECURLOOP)" \
			--file examples/07-workflows/reusable-language-image/build.rl; \
	run_quiet \
		'[workflow] reusable-language-image: use' \
		"$(RECURLOOP)" \
			--import /tmp/recurloop-phrase-language.rli \
			--file examples/07-workflows/reusable-language-image/use.rl; \
	\
	echo; \
	echo '== Reusable syntax image =='; \
	run_quiet \
		'[workflow] reusable-syntax-image: build' \
		"$(RECURLOOP)" \
			--file examples/07-workflows/reusable-syntax-image/build.rl; \
	run_quiet \
		'[workflow] reusable-syntax-image: use' \
		"$(RECURLOOP)" \
			--import /tmp/recurloop-phrase-syntax.rli \
			--file examples/07-workflows/reusable-syntax-image/use.rl; \
	\
	echo; \
	echo '== Shell language =='; \
	run_quiet \
		'[workflow] shell-language: build image' \
		"$(RECURLOOP)" \
			--file examples/07-workflows/shell-language/library.rl; \
	for file in top_level.rl pipeline.rl functions.rl example.rl; do \
		run_quiet \
			"[workflow] shell-language: $$file" \
			"$(RECURLOOP)" \
				--import /tmp/recurloop-shell-library.rli \
				--file "examples/07-workflows/shell-language/$$file"; \
	done; \
	\
	echo; \
	echo '== Amber compatibility =='; \
	"examples/07-workflows/amber-language/run-tests.sh" "$(abspath $(RECURLOOP))"; \
	\
	echo; \
	echo '== Prolog compatibility =='; \
	"examples/07-workflows/prolog-language/run-tests.sh" "$(abspath $(RECURLOOP))"; \
	\
	echo; \
	echo '== Haskell compatibility =='; \
	"examples/07-workflows/haskell-language/run-tests.sh" "$(abspath $(RECURLOOP))"; \
	\
	echo; \
	echo '== Erlang compatibility =='; \
	"examples/07-workflows/erlang-language/run-tests.sh" "$(abspath $(RECURLOOP))"; \
	\
	echo; \
	echo '== Source debugger =='; \
	debug_output="$$(mktemp)"; \
	if "$(RECURLOOP)" \
		--file examples/07-workflows/source-debugger/debugger.rl \
		</dev/null >"$$debug_output" 2>&1; then \
		echo '[workflow] source-debugger: ok'; \
		rm -f "$$debug_output"; \
	else \
		status=$$?; \
		echo "[workflow] source-debugger: FAILED (exit $$status)" >&2; \
		cat "$$debug_output" >&2; \
		rm -f "$$debug_output"; \
		exit "$$status"; \
	fi; \
	\
	echo; \
	echo 'Debugger executable controller: checked by make feature when ptrace is available.'; \
	echo 'All non-interactive examples passed.'


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test: $(RECURLOOP)
	ctest \
		--test-dir "$(CONFIG_DIR)" \
		--output-on-failure \
		--parallel


unit: $(RECURLOOP)
	ctest \
		--test-dir "$(CONFIG_DIR)" \
		-R '\[Unit\]' \
		--output-on-failure \
		--parallel


feature: $(RECURLOOP)
	ctest \
		--test-dir "$(CONFIG_DIR)" \
		-R '\[Feature\]' \
		--output-on-failure


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean:
	@if test -f "$(CONFIG_DIR)/CMakeCache.txt"; then \
		cmake --build "$(CONFIG_DIR)" --target clean; \
	fi
