# Architecture

**Context Marker**: When working with this file, add `📐` to your start-of-message markers.

**Example**:
"🍀 📐 I'm reviewing the architecture of gh-log-cli"

## Overview

- **Single Bash script**: The entire functionality is in `gh-log-ci` (753 lines)
- **GitHub API integration**: Uses GraphQL API v4 for batch queries (explicit REST API v3 mode via `--use-rest`)
- **Caching system**: Success-only caching with TTL to reduce API calls
- **Parallel processing**: Configurable concurrency for REST API mode
- **Watch mode**: Continuous polling with configurable intervals

## API Strategy

- **Primary: GraphQL batch query**: Single query fetches all commit check statuses (lines 221-290)
  - Query structure: Repository → Ref → Target → History(limit) → CheckSuites(100) → CheckRuns(100)
  - Reduces API calls from N to 1 (93% reduction for 15 commits)
  - Transformation: GraphQL JSON → jq → TSV → existing aggregation logic
  - **When to use**: Default mode, optimal for GitHub.com and GitHub Enterprise Server ≥ 3.4
- **REST API mode**: Per-commit API calls with concurrency control (lines 432-553)
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

- **Argument parsing**: Lines 70-119 handle CLI flags and environment variables
- **Commit SHA detection**: Lines 156-167 detect and validate commit SHAs
- **Branch detection**: Lines 169-185 auto-detect branch using GitHub API and git fallbacks (skipped in commit mode)
- **Remote URL parsing**: Lines 194-202 extract owner/repo from GitHub URLs
- **GraphQL functions**: Lines 221-290 handle batch query, transformation, and grouping
  - `fetch_checks_graphql()`: Execute GraphQL batch query with timeout
  - `transform_graphql_response()`: Convert nested JSON to TSV format
  - Parses GraphQL TSV into an associative array for O(1) commit data lookups (eliminates `group_by_sha` O(N*M) lookup)
  - `fetch_checks_graphql_commit()`: Execute GraphQL query for single commit (lines 293-334)
  - `transform_graphql_response_commit()`: Convert single commit JSON to TSV format (lines 336-348)
- **Cache management**: Lines 310-323 read cache with TTL validation
- **Main loop integration**: Lines 303-622 GraphQL or REST mode (controlled by --use-rest flag)
- **Status aggregation**: Shared logic reused for both GraphQL and REST responses
- **Watch mode**: Lines 624-635 implement continuous polling

### Caching System

- **Success-only caching**: Only caches successful commits (line 336)
- **Cache validation**: Requires all three conditions: `OVERALL_ICON=="✅"` AND `RAW_LINES!="__TIMEOUT__"` AND `pending_count==0`
- **Pending check exclusion**: Commits with ANY pending check runs are never cached (prevents incorrect success icon display)
- **TTL-based**: Configurable cache lifetime (default 24 hours)
- **Cache directory**: `~/.cache/gh-log-ci/` or configurable via `LOG_CI_CACHE_DIR`
- **Cache bypass**: `--no-cache` flag forces fresh API calls

### Commit SHA Mode

- **SHA detection**: Lines 156-167 detect and validate commit SHAs
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

- Uses `git log` with custom format for commit display (line 196)
- Implements timeout handling for API calls (lines 198-218)
- Progress spinner shows completed/total count (lines 253-266)
- Status aggregation logic prioritizes failures over pending over success (lines 318-326)
- Watch mode clears screen between iterations (lines 367-368)
- The script requires GitHub CLI (`gh`) to be installed and authenticated
- All API calls go through `gh api` command
- Cache files are named `{owner}_{repo}_success.cache`
- Temporary directories are created for parallel processing output
- The script handles both remote and local branch scenarios
