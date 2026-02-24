# =============================================================================
# GLaDOS Installer — Development Makefile
# =============================================================================

SHELL := /bin/bash
SCRIPT := glados_installer.sh

.PHONY: help lint check dry-run install status clean

## help: Show this help message
help:
	@echo ""
	@echo "  GLaDOS Installer — Development Commands"
	@echo "  ────────────────────────────────────────"
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /' | column -t -s ':'
	@echo ""

## lint: Run ShellCheck static analysis
lint:
	@echo "Running ShellCheck..."
	shellcheck -x -s bash $(SCRIPT) lib/*.sh
	@echo "✔ ShellCheck passed"

## check: Verify bash syntax
check:
	@echo "Checking bash syntax..."
	bash -n $(SCRIPT)
	@echo "✔ Syntax OK"

## dry-run: Execute installer in dry-run mode
dry-run:
	chmod +x $(SCRIPT)
	./$(SCRIPT) --dry-run --verbose

## install: Run the installer
install:
	chmod +x $(SCRIPT)
	./$(SCRIPT)

## status: Show current installation status
status:
	chmod +x $(SCRIPT)
	./$(SCRIPT) --status

## clean: Remove installer logs and lock files
clean:
	rm -rf ~/glados-installer/logs/*
	rm -f /tmp/glados_installer.lock
	@echo "✔ Cleaned logs and lock files"
