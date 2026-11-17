PREFIX ?= /usr
DESTDIR ?=
ZIG ?= zig
ZIG_FLAGS ?= -Doptimize=ReleaseFast

.PHONY: all build test install clean aur-push

all: build

build:
	$(ZIG) build $(ZIG_FLAGS)

test:
	$(ZIG) build test --summary all

install: build
	install -Dm755 zig-out/bin/zource "$(DESTDIR)$(PREFIX)/bin/zource"
	install -Dm644 man/zource.1 "$(DESTDIR)$(PREFIX)/share/man/man1/zource.1"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/zource/README.md"
	install -Dm644 LICENSE "$(DESTDIR)$(PREFIX)/share/licenses/zource/LICENSE"

clean:
	rm -rf .zig-cache zig-cache zig-out

aur-push:
	./scripts/push-aur.sh
