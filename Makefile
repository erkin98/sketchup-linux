.PHONY: all lint test install-dev clean help

SCRIPT      := install.sh
LEGACY      := install-sketchup.sh
TESTS       := tests/install.bats
BATS        := bats

all: lint test

## lint: Run ShellCheck on all scripts
lint:
	@echo "→ shellcheck $(SCRIPT)"
	@shellcheck $(SCRIPT)
	@echo "→ shellcheck $(LEGACY)"
	@shellcheck $(LEGACY)
	@echo "→ bash -n syntax check"
	@bash -n $(SCRIPT)
	@bash -n $(LEGACY)
	@echo "All checks passed."

## test: Run bats test suite
test:
	@echo "→ bats $(TESTS)"
	@$(BATS) $(TESTS)

## install-dev: Install development dependencies (ShellCheck + bats-core)
install-dev:
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y shellcheck bats; \
	elif command -v dnf >/dev/null 2>&1; then \
		sudo dnf install -y ShellCheck bats; \
	elif command -v pacman >/dev/null 2>&1; then \
		sudo pacman -S --noconfirm shellcheck bash-bats; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install shellcheck bats-core; \
	else \
		echo "Could not detect package manager. Install shellcheck and bats-core manually."; \
		exit 1; \
	fi

## dry-run: Preview install.sh without making any changes
dry-run:
	@bash $(SCRIPT) --dry-run

## clean: Remove generated files
clean:
	@rm -f ~/sketchup-steam-config.txt
	@echo "Cleaned."

## help: Show this help
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
