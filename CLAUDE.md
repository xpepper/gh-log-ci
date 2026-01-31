# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Common Development Commands

```bash
# Run all tests (shellcheck + bats)
make test

# Run shellcheck only
make shellcheck

# Run bats tests only
make bats

# Run a specific test file
bats tests/help.bats

# Run local CI script
make ci-local

# Clean cache files
make clean-cache

# Run the extension
make run
# or
./gh-log-ci

# Testing commit SHA mode
./gh-log-ci 7b60fc9           # Show status for specific commit
./gh-log-ci $(git rev-parse HEAD~5)  # Use full SHA
```

## Architecture Overview

This is a **single Bash script** (`gh-log-ci`) that implements a GitHub CLI extension. The script fetches CI status for commits via GitHub Checks API and displays them inline with git log output.

**Key Design Patterns:**

- **Commit SHA Detection**: Validates and resolves SHAs using `git rev-parse --verify`
- **Caching**: Success-only caching with three-condition validation (icon + no timeout + no pending)
- **Event-Based Filtering**: Excludes non-push workflows from status aggregation
- **Parallel Processing**: Configurable concurrency for REST API mode
- **Watch Mode**: Continuous polling with screen clearing

For detailed technical implementation, see [Architecture](.claude/architecture.md).

## Testing Notes

- **Bats tests** are in `tests/` directory
- Tests expect to run from the project root (script path is `$(pwd)/gh-log-ci`)
- Each test file covers a specific feature area (help, cache, timeout, watch, pending)
- Cache tests verify the critical pending_count validation that prevents incorrect success icons

For complete test structure and environment variables, see [Testing](.claude/testing.md).
