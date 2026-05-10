PREFIX ?= ~/.local
BINDIR ?= $(PREFIX)/bin
ICLOUD_BINDIR ?= $(HOME)/Library/Mobile Documents/com~apple~CloudDocs/Applications/bin
CONFIG ?= release

.PHONY: build test install install-iCloud clean

build:
	swift build -c $(CONFIG)

test:
	swift test

install: build
	@mkdir -p $(BINDIR)
	@rm -f $(BINDIR)/ow
	cp .build/$(CONFIG)/ow $(BINDIR)/

install-iCloud: build
	@mkdir -p "$(ICLOUD_BINDIR)"
	@rm -f "$(ICLOUD_BINDIR)/ow"
	cp .build/$(CONFIG)/ow "$(ICLOUD_BINDIR)/"

clean:
	swift package clean
