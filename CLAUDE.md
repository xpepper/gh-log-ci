# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

# Common Development Commands

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
```

# Architecture Overview

This is a **single Bash script** (`gh-log-ci`) that implements a GitHub CLI extension. The script fetches CI status for commits via GitHub Checks API and displays them inline with git log output.

## Key Design Patterns

**Caching System (lines 234-248, 336-342):**
- Success-only caching: only commits with ALL checks passing are cached
- Cache validation requires three conditions: `OVERALL_ICON=="✅"` AND `RAW_LINES!="__TIMEOUT__"` AND `pending_count==0`
- Prevents displaying incorrect success icons for commits with pending builds
- TTL-based expiration (default 24h)

**Parallel Processing (lines 274-350):**
- Background processes with configurable concurrency limit
- Temporary directory for parallel output coordination
- Waits for all background jobs to complete before aggregation

**Status Aggregation (lines 290-326):**
- Priority order: failure > cancelled > pending > success
- Special handling for "blocked" queued runs (🔁 icon) vs normal pending
- Maps GitHub check conclusions to emoji icons

**Watch Mode (lines 365-378):**
- Continuous polling loop with configurable interval
- Clears screen between iterations for clean display
- Integrates with caching to avoid redundant API calls

# Testing Notes

- **Bats tests** are in `tests/` directory
- Tests expect to run from the project root (script path is `$(pwd)/gh-log-ci`)
- Each test file covers a specific feature area (help, cache, timeout, watch, pending)
- Cache tests verify the critical pending_count validation that prevents incorrect success icons
