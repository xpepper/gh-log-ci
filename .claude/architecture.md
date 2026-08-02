# Architecture

**Context Marker**: When working with this file, add `📐` to your start-of-message markers.

**Example**:
"🍀 📐 I'm reviewing the architecture of gh-log-cli"

## Overview

- **Single Bash script**: The entire functionality is in `gh-log-ci`
- **Bash 4.0+ required**: The script guards on `BASH_VERSINFO` at the top and exits with an
  actionable error on older shells (notably macOS's default Bash 3.2). Associative arrays are
  therefore fair game.
- **GitHub API integration**: Uses GraphQL API v4 for batch queries (explicit REST API v3 mode via `--use-rest`)
- **Caching system**: Success-only caching with TTL to reduce API calls
- **Parallel processing**: Configurable concurrency for REST API mode
- **Watch mode**: Continuous polling with configurable intervals

## Constraints

- **Single-script architecture**: The entire implementation stays in the one `gh-log-ci` script.
  Do not extract features into separate files or libraries unless the single-file constraint
  becomes demonstrably unmaintainable (>2000 lines with no clear organization). As a `gh`
  extension, single-file distribution keeps `gh extension install` self-contained, with no
  module loading or PATH complexity.
- **Strict error propagation**: The script runs under `set -euo pipefail`.
- **API failures** surface as the ⏲ icon rather than a crash or a false ✅.
- **Cache failures** fall back to fresh API calls.

## API Strategy

- **Primary: GraphQL batch query**: Single query fetches all commit check statuses
  - Query structure: Repository → Ref → Target → History(limit) → CheckSuites(100) → CheckRuns(100)
  - Reduces API calls from N to 1 (93% reduction for 15 commits)
  - Transformation: GraphQL JSON → jq → TSV → existing aggregation logic
  - **When to use**: Default mode, optimal for GitHub.com and GitHub Enterprise Server ≥ 3.4
- **REST API mode**: Per-commit API calls with concurrency control
  - Manual override: `--use-rest` flag or `LOG_CI_FORCE_REST=1` environment variable
  - **When to use**:
    - GitHub Enterprise Server < 3.4 (GraphQL Checks API unavailable)
    - Commits with >100 check suites (GraphQL query limit)
    - GraphQL API errors or timeouts
    - Debugging or comparing GraphQL vs REST behavior
  - Concurrency controlled via `--concurrency` flag (default: 4 parallel requests)
- **Error handling**: GraphQL errors fail fast with clear error messages suggesting `--use-rest` flag
- **Response handling**: Both APIs use identical status aggregation and icon mapping logic

## Key Components

### Main Script (`gh-log-ci`)

Grep for the function name to locate each piece — the script is a single file and line
numbers go stale on every commit.

- **Bash version guard**: `BASH_VERSINFO` check at the top of the file, before anything else runs
- **Argument parsing**: Inline flag/env loop near the top, sets the `LOG_CI_*`-backed variables
- **Commit SHA detection**: Sets `IS_COMMIT_MODE`, validating with `git rev-parse --verify`
- **Branch detection**: Auto-detects via GitHub API with git fallbacks (skipped in commit mode)
- **Remote URL parsing**: Extracts owner/repo from GitHub URLs
- **GraphQL functions**:
  - `fetch_checks_graphql()`: Execute GraphQL batch query with timeout
  - `transform_graphql_response()`: Convert nested JSON to TSV format
  - `group_by_sha()`: Extract check runs for a specific commit SHA, using an associative array
    built once from the TSV so lookups are O(1) rather than a subshell search per commit
  - `fetch_checks_graphql_commit()`: Execute GraphQL query for a single commit
  - `transform_graphql_response_commit()`: Convert single commit JSON to TSV format
- **Cache management**: Reads cache with TTL validation
- **Main loop integration**: GraphQL or REST mode (controlled by `--use-rest`)
- **Status aggregation**: Shared logic reused for both GraphQL and REST responses
- **Watch mode**: Continuous polling loop

### Caching System

- **Success-only caching**: Only caches successful commits
- **Cache validation**: Requires all three conditions: `OVERALL_ICON=="✅"` AND `RAW_LINES!="__TIMEOUT__"` AND `pending_count==0`
- **Pending check exclusion**: Commits with ANY pending check runs are never cached (prevents incorrect success icon display)
- **TTL-based**: Configurable cache lifetime (default 24 hours)
- **Cache directory**: `~/.cache/gh-log-ci/` or configurable via `LOG_CI_CACHE_DIR`
- **Cache bypass**: `--no-cache` flag forces fresh API calls

### Commit SHA Mode

- **SHA detection**: Validates with `git rev-parse --verify <sha>^{commit}`
- **Single commit GraphQL**: `fetch_checks_graphql_commit()` and `transform_graphql_response_commit()` functions
- **Conditional logic**: `IS_COMMIT_MODE` flag controls branch vs commit mode throughout script

### Event-Based Filtering

- **Purpose**: Exclude non-push workflows from status aggregation while keeping them visible
- **Implementation**: Add EXCLUDED flag (5th TSV column) based on `workflowRun.event != "push"`
- **Display behavior**: Excluded checks shown with 🤖 icon and `[non-push]` label when using `-C`
- **Aggregation**: Checks with EXCLUDED=1 skipped when computing overall status icon
- **GraphQL functions**: `transform_graphql_response()` and `transform_graphql_response_commit()`
- **REST mode limitation**: All checks marked EXCLUDED=0 (event types not available in REST API)
- **Matching behavior**: Aligns with GitHub's `statusCheckRollup` logic (only includes push events)

## Implementation Details

- Uses `git log` with a custom tab-delimited format for commit display
- Implements timeout handling for API calls
- Progress spinner shows completed/total count
- Status aggregation logic prioritizes failures over pending over success
- Watch mode clears the screen between iterations
- The script requires GitHub CLI (`gh`) to be installed and authenticated
- All API calls go through `gh api` command
- Cache files are named `{owner}_{repo}_success.cache`
- Temporary directories are created for parallel processing output
- The script handles both remote and local branch scenarios
