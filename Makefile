SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := build

PREFIX ?= /usr
DESTDIR ?=
ZIG_FLAGS ?= -Doptimize=ReleaseFast
MISE_BIN := $(shell command -v mise 2>/dev/null || echo "$(HOME)/.local/bin/mise")

# Prefer active zig in PATH (e.g. Arch makepkg chroot or activated mise shell);
# otherwise execute via mise using mise.toml.
ZIG_CMD := $(shell if command -v zig >/dev/null 2>&1; then echo "zig"; elif [ -x "$(MISE_BIN)" ]; then echo "$(MISE_BIN) exec -- zig"; else echo ""; fi)

.PHONY: help all bootstrap setup deps build test run man install uninstall clean aur-push

help: ## Show available Makefile targets
	@printf "zource Makefile targets:\n\n"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

all: build ## Build release binary

bootstrap: ## Install mise (if missing), trust mise.toml, and install pinned Zig toolchain
	@if ! command -v mise >/dev/null 2>&1 && [ ! -x "$(MISE_BIN)" ]; then \
		echo "==> Installing mise into $(HOME)/.local/bin/mise..."; \
		curl -fsSL https://mise.run | sh; \
	fi
	@"$(MISE_BIN)" trust --yes mise.toml >/dev/null 2>&1 || "$(MISE_BIN)" trust mise.toml
	@"$(MISE_BIN)" install
	@echo "==> Toolchain ready: $$("$(MISE_BIN)" exec -- zig version)"

setup: bootstrap ## Alias for bootstrap
deps: bootstrap ## Alias for bootstrap

build: ## Compile release zource binary (zig-out/bin/zource)
	@if [ -z "$(ZIG_CMD)" ]; then $(MAKE) --no-print-directory bootstrap; fi
	@if command -v zig >/dev/null 2>&1; then \
		zig build $(ZIG_FLAGS); \
	else \
		"$(MISE_BIN)" exec -- zig build $(ZIG_FLAGS); \
	fi

test: ## Run unit test suite
	@if [ -z "$(ZIG_CMD)" ]; then $(MAKE) --no-print-directory bootstrap; fi
	@if command -v zig >/dev/null 2>&1; then \
		zig build test --summary all; \
	else \
		"$(MISE_BIN)" exec -- zig build test --summary all; \
	fi

run: build ## Build and launch zource on the current repository
	./zig-out/bin/zource .

man: ## View the local zource(1) manual page
	man -l ./man/zource.1

install: build ## Install binary, man page, docs, and license under DESTDIR/PREFIX
	install -Dm755 zig-out/bin/zource "$(DESTDIR)$(PREFIX)/bin/zource"
	install -Dm644 man/zource.1 "$(DESTDIR)$(PREFIX)/share/man/man1/zource.1"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/zource/README.md"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/zource/LICENSE"

uninstall: ## Remove installed zource files from DESTDIR/PREFIX
	rm -f "$(DESTDIR)$(PREFIX)/bin/zource"
	rm -f "$(DESTDIR)$(PREFIX)/share/man/man1/zource.1"
	rm -rf "$(DESTDIR)$(PREFIX)/share/doc/zource"
	rm -rf "$(DESTDIR)$(PREFIX)/share/licenses/zource"

clean: ## Remove Zig build caches and zig-out/
	rm -rf .zig-cache zig-cache zig-out

aur-push: ## Verify live GitHub tag tarball with makepkg and push to AUR
	./scripts/push-aur.sh
