PREFIX ?= $(HOME)/.local/bin

.PHONY: build test install uninstall

build:
	swift build -c release

test:
	swift test

install: build
	mkdir -p $(PREFIX)
	rm -f $(PREFIX)/earshot  # new inode, or macOS kills the stale signature (Killed: 9)
	cp .build/release/earshot $(PREFIX)/earshot
	@echo "installed $(PREFIX)/earshot"
	@case ":$$PATH:" in *":$(PREFIX):"*) ;; *) echo "note: add $(PREFIX) to your PATH";; esac

uninstall:
	@if [ -x $(PREFIX)/earshot ]; then $(PREFIX)/earshot uninstall-hooks; fi
	rm -f $(PREFIX)/earshot
