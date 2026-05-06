PREFIX ?= ~/.local
BINDIR ?= $(PREFIX)/bin
CONFIG ?= release

.PHONY: build test install clean

build:
	swift build -c $(CONFIG)

test:
	swift test

install: build
	@mkdir -p $(BINDIR)
	@rm -f $(BINDIR)/ow
	cp .build/$(CONFIG)/ow $(BINDIR)/

clean:
	swift package clean
