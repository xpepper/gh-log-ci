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

# Testing commit SHA mode
./gh-log-ci 7b60fc9           # Show status for specific commit
./gh-log-ci $(git rev-parse HEAD~5)  # Use full SHA
```

# Architecture Overview

This is a **single Bash script** (`gh-log-ci`) that implements a GitHub CLI extension. The script fetches CI status for commits via GitHub Checks API and displays them inline with git log output.

## Key Design Patterns

**Commit SHA Detection (lines 156-167):**
- Detects if positional argument is a valid commit SHA (full or short)
- Uses `git rev-parse --verify` to validate and resolve SHAs
- Skips branch detection and remote fetch when in commit mode
- Sets `IS_COMMIT_MODE=1` and `COMMIT_SHA=<resolved-full-sha>`

**Single Commit Mode:**
- GraphQL query uses `repository.object(expression: $sha)` instead of `ref.target.history`
- Git log uses `git log $COMMIT_SHA -n 1` instead of branch-based log
- No remote branch warnings or unnecessary output
- Functions: `fetch_checks_graphql_commit()` (lines 293-334) and `transform_graphql_response_commit()` (lines 336-348)

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

**Time-Based Filtering (lines 67-68, 342-388, 579-592):**
- Filters check suites by creation time relative to commit time
- Default threshold: 4 hours after commit (14400 seconds)
- Adds EXCLUDED flag (0 or 1) as 5th TSV column
- Prevents scheduled/periodic workflows from affecting commit status icon
- Excluded checks still displayed with `-C` flag, marked with ⏱ icon
- Configurable via `LOG_CI_TIME_FILTER_HOURS` environment variable
- Applied in both `transform_graphql_response()` and `transform_graphql_response_commit()`
- REST mode marks all checks as EXCLUDED=0 (limitation: no suite timestamps)

# Testing Notes

- **Bats tests** are in `tests/` directory
- Tests expect to run from the project root (script path is `$(pwd)/gh-log-ci`)
- Each test file covers a specific feature area (help, cache, timeout, watch, pending)
- Cache tests verify the critical pending_count validation that prevents incorrect success icons
