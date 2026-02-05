# Failure Context & Exit Codes Design

**Date:** 2026-02-05  
**Status:** Draft  
**Goal:** Make failures easier to understand and enable CI/script integration

## Overview

This design adds two capabilities to `gh-log-ci`:

1. **Exit codes** for automation (CI gates, pre-push hooks, scripts)
2. **Verbose failure context** to understand what failed and why

## Feature 1: Exit Codes

### Behavior

- Exit 0 when all displayed commits have ✅ (success) status
- Exit 1 when any commit has ❌ (failure) or ⚠ (mixed) status
- Pending 🕓, cancelled 🚫, and timeout ⏲ count as "not failed" (exit 0)

### Flag

- `--no-fail` - always exit 0 regardless of status (for view-only usage)
- Environment variable: none (exit codes enabled by default)

### Use Cases

```bash
# Pre-push hook: block push if recent commits failing
gh log-ci -n 5 || echo "CI failures detected, consider fixing first"

# CI gate: verify branch health before deploy
gh log-ci --branch main -n 10 || exit 1

# Just viewing, don't want script to fail
gh log-ci --no-fail
```

### Implementation Notes

- Calculated after all commits are processed
- In watch mode, exit code reflects final state when interrupted (Ctrl+C)
- Commit SHA mode: exit 1 if that specific commit is failing

## Feature 2: Verbose Failure Details (`--verbose` / `-v`)

### Output Format

When `-v` is used (extends existing `-C` checks output):

```
❌  c4f35260a - feat(auth): add MFA (Wed Oct 22 09:25:09 2025) <John Smith>
    ├─ ❌ test / ubuntu-latest [push]
    │     → https://github.com/owner/repo/actions/runs/12345
    │     Error: Process completed with exit code 1.
    ├─ ❌ test / macos-latest [push]  
    │     → https://github.com/owner/repo/actions/runs/12346
    │     Error: npm test failed
    └─ ✅ lint / eslint [push]
```

### What `-v` Adds Over `-C`

- **Direct links** to each check run (clickable in most terminals)
- **Error summary** - last meaningful line from failure output (fetched via API)

### Flags Interaction

| Flags | Behavior |
|-------|----------|
| `-C` alone | Shows check names + status (current behavior) |
| `-v` alone | Implies `-C`, adds links + error summaries |
| `-Cv` | Same as `-v` |

### API Consideration

Error summaries require an extra API call per failed check. We only fetch for failed checks to minimize overhead.

### Environment Variable

- `LOG_CI_VERBOSE=1` - equivalent to `-v`

## Feature 3: Failure History (`--fail-history`)

### Purpose

Distinguish flaky tests from real regressions by showing if the same check failed on previous commits.

### Output Format

Extends `-v` output:

```
❌  c4f35260a - feat(auth): add MFA (Wed Oct 22 09:25:09 2025) <John Smith>
    ├─ ❌ test / ubuntu-latest [push] ← also failed on 2 previous commits
    │     → https://github.com/owner/repo/actions/runs/12345
    └─ ❌ build / node-18 [push] ← NEW failure (was ✅ on previous)
```

### How It Works

- Compares failed check names against the same checks on previous N commits (already fetched)
- "NEW failure" = this check passed on the immediately previous commit
- "also failed on X previous" = same check failing consistently

### Flags

- `--fail-history` - enables this analysis
- Requires at least 2 commits to compare (automatically increases limit if needed)
- Environment variable: `LOG_CI_FAIL_HISTORY=1`

### Trade-off

No extra API calls needed since we already have check data for displayed commits. Just cross-references the data we have.

## Implementation Plan

### Priority Order

| Order | Feature | Complexity | Value | Effort |
|-------|---------|------------|-------|--------|
| 1 | Exit codes | Low | High | ~1 hour |
| 2 | Verbose links | Medium | High | ~2 hours |
| 3 | Error summaries | Medium | High | ~3 hours |
| 4 | Failure history | Low | Medium | ~2 hours |

### Step-by-Step

#### Phase 1: Exit Codes
1. Add `--no-fail` flag parsing
2. Track overall status during commit processing
3. Set exit code at script end based on status
4. Handle watch mode exit on Ctrl+C
5. Add tests for exit code behavior

#### Phase 2: Verbose Links
1. Add `-v` / `--verbose` flag parsing
2. Modify check output to include `html_url` from API response
3. Format links in tree-style output
4. Add tests for verbose output format

#### Phase 3: Error Summaries
1. For failed checks, fetch annotations/logs via API
2. Extract last meaningful error line
3. Display inline under each failed check
4. Cache within session to avoid redundant calls
5. Add tests for error extraction

#### Phase 4: Failure History
1. After fetching all commits, build check-name → status map per commit
2. For failed checks, look up same check on previous commits
3. Annotate with "NEW failure" or "also failed on X previous"
4. Add tests for history detection

## Help Text Updates

```
Options:
  --verbose, -v          Show detailed failure info (links, error summaries)
  --fail-history         Show if failures are new or recurring
  --no-fail              Always exit 0 (disable exit codes for CI)
```

## README Updates

Add to Icons Legend:
- Document exit code behavior in a new "Exit Codes" section
- Add examples for CI integration and pre-push hooks

## Testing Strategy

- Unit tests for exit code logic (bats)
- Unit tests for verbose output formatting
- Integration tests with mock API responses
- Manual testing with real repositories
