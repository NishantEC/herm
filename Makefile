.PHONY: install uninstall test lint check

PREFIX ?= $(HOME)/.local
BIN_DIR := $(PREFIX)/bin
REPO_DIR := $(shell pwd)

install:
	@mkdir -p $(BIN_DIR)
	@ln -sf $(REPO_DIR)/bin/herm $(BIN_DIR)/herm
	@echo "Installed: $(BIN_DIR)/herm -> $(REPO_DIR)/bin/herm"
	@echo "Make sure $(BIN_DIR) is on your PATH."

uninstall:
	@rm -f $(BIN_DIR)/herm
	@echo "Removed: $(BIN_DIR)/herm"

test:
	@bats tests/cli

lint:
	@shellcheck bin/herm cli/lib.sh cli/commands/*.sh cloud-init/scripts/*.sh
	@cd terraform && terraform fmt -check -recursive && terraform validate

check: lint test
