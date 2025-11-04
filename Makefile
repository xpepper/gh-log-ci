#!/usr/bin/make -f

# gh-log-ci Makefile
# Common tasks for development and maintenance

# Default cache directory
CACHE_DIR ?= $(HOME)/.cache/gh-log-ci

# Default target
.PHONY: help
help: ## Show this help
	@echo "gh-log-ci Makefile targets:"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: test
test: ## Run all tests (shellcheck + bats)
	@echo "Running shellcheck..."
	shellcheck gh-log-ci
	@echo "Running bats tests..."
	bats tests

.PHONY: shellcheck
shellcheck: ## Run shellcheck only
	shellcheck gh-log-ci

.PHONY: bats
bats: ## Run bats tests only
	bats tests

.PHONY: ci-local
ci-local: ## Run local CI script
	./ci-local.sh

.PHONY: clean-cache
clean-cache: ## Remove all cache files
	@echo "Removing cache files from $(CACHE_DIR)..."
	@rm -f $(CACHE_DIR)/*_success.cache
	@echo "Cache files removed."

.PHONY: clean-cache-all
clean-cache-all: ## Remove entire cache directory
	@echo "Removing entire cache directory $(CACHE_DIR)..."
	@rm -rf $(CACHE_DIR)
	@echo "Cache directory removed."

.PHONY: install-deps-macos
install-deps-macos: ## Install dependencies on macOS (requires Homebrew)
	brew install shellcheck bats-core

.PHONY: install-deps-ubuntu
install-deps-ubuntu: ## Install dependencies on Ubuntu
	sudo apt-get update && sudo apt-get install -y shellcheck bats

.PHONY: list-cache
list-cache: ## List cache files
	@echo "Cache files in $(CACHE_DIR):"
	@ls -la $(CACHE_DIR) 2>/dev/null || echo "No cache directory found"

.PHONY: run
run: ## Run gh-log-ci with default settings
	./gh-log-ci