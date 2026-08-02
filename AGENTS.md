# gh-log-ci Development Guidelines

## Project Overview

gh-log-ci is a GitHub CLI extension that displays CI status next to commit logs. It shows recent commits with inline summary icons indicating GitHub Check/Actions status (green, failing, pending, or cancelled).

This is a **single Bash script** (`gh-log-ci`) that implements the extension, fetching CI status via GitHub Checks API and displaying it inline with git log output.

To get more info, just run `./gh-log-ci --help`.

**Context Marker**: When working with this file, add `🪵` to your start-of-message markers.

**Example**:
"🍀 🪵 Let's implement the requested feature..."

## Quick Reference

**Commands:**
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
./gh-log-ci 7b60fc9                      # Show status for specific commit
./gh-log-ci $(git rev-parse HEAD~5)      # Use full SHA
```

**Technologies:**
- Bash 4.0+ (single script)
- GitHub CLI (`gh`)
- GraphQL API v4 (primary) or REST API v3 (`--use-rest`)

**Bash 4.0+ is a hard requirement.** The script refuses to run on older shells, so associative
arrays and other Bash 4 features are allowed. Note that macOS ships Bash 3.2 as `/bin/bash`;
develop against a Homebrew Bash (`brew install bash`).

## Key Design Patterns

- **Commit SHA Detection**: Validates and resolves SHAs using `git rev-parse --verify`
- **Caching**: Success-only caching with three-condition validation (icon + no timeout + no pending)
- **Event-Based Filtering**: Excludes non-push workflows from status aggregation
- **Parallel Processing**: Configurable concurrency for REST API mode
- **Watch Mode**: Continuous polling with screen clearing

## Testing Notes

- **Bats tests** are in `tests/` directory
- Tests expect to run from the project root (script path is `$(pwd)/gh-log-ci`)
- Each test file covers a specific feature area: help, cache, timeout, watch flags, pending
  icon, commit SHA mode, event filtering, GraphQL batching, and the Bash version guard
- Cache tests verify the critical pending_count validation that prevents incorrect success icons

## Detailed Guidelines

For specific topics, see:

- [Architecture](.claude/architecture.md) - Technical implementation, API strategy, caching, event filtering
- [Development Workflow](.claude/development.md) - Development rules, CI/CD, common commands
- [Testing](.claude/testing.md) - Test structure, environment variables
- [Web Search](.claude/perplexity.md) - Using Perplexity CLI for research
