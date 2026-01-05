# Data Model: GraphQL Batch Query Implementation

**Date**: 2026-01-06
**Feature**: GraphQL batch query for check statuses

## Overview

This document defines data structures, transformations, and state management for the GraphQL batch query implementation. The design maintains compatibility with existing REST API data flow while introducing GraphQL-specific structures.

## Core Entities

### 1. CommitCheckData

**Purpose**: Represents aggregated check run status for a single commit

**Bash Implementation**:
```bash
# Associative arrays (indexed by commit SHA)
declare -A SHA_MAP          # Index → SHA
declare -A LINE_MAP         # Index → Git log line
declare -A SUCCESS_CACHE    # SHA → timestamp (success-only cache)

# Per-commit counters (calculated during aggregation)
success_count=0
fail_count=0
cancel_count=0
pending_count=0
other_count=0
total_count=0
```

**Attributes**:
- `sha`: Commit SHA (40-character hex string)
- `log_line`: Formatted git log output (color-coded, includes metadata)
- `overall_icon`: Aggregated status icon (✅, ❌, 🕓, 🔁, 🚫, ⚠, ⏲, ➖, ❔)
- `success_count`: Number of successful check runs
- `fail_count`: Number of failed check runs
- `cancel_count`: Number of cancelled check runs
- `pending_count`: Number of pending/in-progress check runs
- `other_count`: Number of neutral/skipped/stale check runs
- `total_count`: Total number of check runs
- `detail_output`: Per-check run details (only if `--checks` flag set)
- `cached`: Boolean flag indicating if data loaded from cache

**State Transitions**:
```
Initial → [API Fetch] → Aggregated → [Icon Assignment] → Cached (if success)
                     ↓
                  Timeout → [Show ⏲] → Not Cached
```

### 2. CheckRun

**Purpose**: Individual check run status (CI job, test suite, linter, etc.)

**REST API Format** (current):
```
NAME<TAB>STATUS<TAB>CONCLUSION
```

**GraphQL Format** (new):
```json
{
  "name": "string",
  "status": "QUEUED|IN_PROGRESS|COMPLETED",
  "conclusion": "SUCCESS|FAILURE|NEUTRAL|CANCELLED|SKIPPED|TIMED_OUT|ACTION_REQUIRED|STALE|null"
}
```

**Unified Internal Format** (tab-delimited string):
```
NAME<TAB>STATUS<TAB>CONCLUSION
```

**Attributes**:
- `name`: Check run name (e.g., "build", "lint", "test-unit")
- `status`: Execution status (`queued`, `in_progress`, `completed`)
- `conclusion`: Final result (only set if `status == "completed"`)

**Status Values**:
- `QUEUED`: Check run is queued but not started
- `IN_PROGRESS`: Check run is currently executing
- `COMPLETED`: Check run finished (check `conclusion` for result)
- Empty string: Unknown status (treat as pending)

**Conclusion Values**:
- `SUCCESS` / `success`: Check passed
- `FAILURE` / `failure`: Check failed
- `NEUTRAL` / `neutral`: Check completed but neither passed nor failed
- `CANCELLED` / `cancelled`: Check was cancelled
- `SKIPPED` / `skipped`: Check was skipped
- `TIMED_OUT` / `timed_out`: Check exceeded time limit
- `ACTION_REQUIRED` / `action_required`: Manual intervention needed
- `STALE` / `stale`: Check result is outdated
- Empty string / `null`: No conclusion (check still running or queued)

### 3. GraphQLResponse

**Purpose**: Raw response from GitHub GraphQL API

**Structure**:
```json
{
  "data": {
    "repository": {
      "ref": {
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "abc123...",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {
                            "name": "build",
                            "status": "COMPLETED",
                            "conclusion": "SUCCESS"
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }
  }
}
```

**Transformation Path**:
```
GraphQL JSON → jq extraction → TSV format → Aggregation loop → Icon assignment
```

### 4. CacheEntry

**Purpose**: Persisted success-only cache for commits

**File Format**: `$CACHE_DIR/{owner}_{repo}_success.cache`
```
SHA<TAB>EPOCH_TIMESTAMP
SHA<TAB>EPOCH_TIMESTAMP
...
```

**Attributes**:
- `sha`: Commit SHA (cache key)
- `timestamp`: Unix epoch seconds when cached

**Validation Rules**:
1. Cache hit only if `timestamp + CACHE_TTL > NOW`
2. Only cache if `overall_icon == "✅"` AND `pending_count == 0` AND `RAW_LINES != "__TIMEOUT__"`
3. Cache bypass if `--no-cache` flag set or `SHOW_CHECKS == 1`

**Cache Lifecycle**:
```
[Fetch Checks] → [Aggregate Status] → [If Success] → [Write to Cache]
                                    ↓
                                [If Pending] → [Skip Cache]
```

## Data Flow

### Current REST API Flow

```
1. git log → extract SHAs
2. For each SHA (parallel, concurrency=N):
   a. gh api /repos/{owner}/{repo}/commits/{sha}/check-runs
   b. Parse JSON → TSV (NAME\tSTATUS\tCONCLUSION)
   c. Aggregate status → assign icon
   d. Write to temp file
   e. If success, write to cache
3. Read temp files in order → display
```

### New GraphQL Flow

```
1. git log → extract SHAs
2. Check cache for each SHA:
   a. If all cached → display from cache (skip API)
   b. If any uncached → proceed to GraphQL
3. Single GraphQL query:
   a. gh api graphql -f query='...' -f owner=X -f repo=Y -f branch=Z -F limit=N
   b. Parse nested JSON → flatten to TSV (SHA\tNAME\tSTATUS\tCONCLUSION)
4. Group by SHA:
   a. For each SHA, aggregate check runs → assign icon
   b. Write to temp file
   c. If success, write to cache
5. Read temp files in order → display
```

### Fallback Flow

```
1. Attempt GraphQL query
2. If error (schema unsupported, timeout, permission denied):
   a. Log fallback (if debug mode)
   b. Execute existing REST API flow
3. Display results (identical to REST API)
```

## Aggregation Logic

**Icon Priority** (highest to lowest):
1. `⏲` (Timeout): If API timeout occurred
2. `❌` (Failure): If `fail_count > 0`
3. `🕓` (Pending): If `pending_count > 0` AND `fail_count == 0`
4. `🔁` (Blocked Queued): If queued run blocked by in-progress run of same workflow
5. `🚫` (Cancelled): If `cancel_count > 0` AND `fail_count == 0` AND `pending_count == 0`
6. `✅` (Success): If `success_count > 0` AND `fail_count == 0` AND `pending_count == 0`
7. `❔` (Unknown): Fallback if no check runs or unrecognized status

**Aggregation Algorithm**:
```bash
for each CheckRun in commit:
  if status != "completed" AND conclusion is empty:
    pending_count++
    icon = "🕓"
  elif conclusion == "success":
    success_count++
    icon = "✅"
  elif conclusion in ["failure", "timed_out", "action_required"]:
    fail_count++
    icon = "❌"
  elif conclusion == "cancelled":
    cancel_count++
    icon = "🚫"
  elif conclusion in ["neutral", "skipped", "stale"]:
    other_count++
    icon = "➖"
  else:
    other_count++
    icon = "❔"
end for

overall_icon = determine_overall_icon(fail_count, pending_count, cancel_count, success_count)
```

**Special Case: Blocked Queued Detection**

For commits with queued runs, detect if blocked by in-progress workflow:
```bash
# Group check runs by workflow name
# If any workflow has:
#   - One run with status="in_progress"
#   - Another run with status="queued"
# Then: mark as blocked (🔁 icon takes precedence over 🕓)
```

This logic is implemented in existing code (lines 352-370) and must be ported to work with GraphQL response format.

## Transformation Functions

### 1. `transform_graphql_response()`

**Purpose**: Convert nested GraphQL JSON to flat TSV format

**Input**: GraphQL response JSON (from `gh api graphql`)
**Output**: Tab-delimited text (one line per check run)

**jq Pipeline**:
```bash
jq -r '
  .data.repository.ref.target.history.nodes[] as $commit |
  $commit.oid as $sha |
  (
    $commit.checkSuites.nodes[]? |
    .checkRuns.nodes[]? |
    [$sha, .name, (.status // ""), (.conclusion // "")]
  ) |
  @tsv
' <<< "$graphql_response"
```

**Output Example**:
```
abc123...	build	COMPLETED	SUCCESS
abc123...	lint	COMPLETED	SUCCESS
def456...	test	IN_PROGRESS
def456...	build	COMPLETED	FAILURE
```

### 2. `group_by_sha()`

**Purpose**: Group flat TSV by commit SHA for aggregation

**Input**: Flat TSV from `transform_graphql_response()`
**Output**: Per-SHA arrays for aggregation loop

**Implementation**:
```bash
declare -A CHECK_DATA  # SHA → TSV lines for that commit

while IFS=$'\t' read -r SHA NAME STATUS CONCLUSION; do
  if [[ -z "${CHECK_DATA[$SHA]:-}" ]]; then
    CHECK_DATA[$SHA]="$NAME\t$STATUS\t$CONCLUSION"
  else
    CHECK_DATA[$SHA]+=$'\n'"$NAME\t$STATUS\t$CONCLUSION"
  fi
done < <(transform_graphql_response "$graphql_response")

# Then iterate CHECK_DATA keys (SHAs) and aggregate
```

### 3. `normalize_status_case()`

**Purpose**: Convert GraphQL UPPERCASE status/conclusion to lowercase for consistency with REST API format

**Input**: `COMPLETED`, `SUCCESS`, `IN_PROGRESS`, etc.
**Output**: `completed`, `success`, `in_progress`, etc.

**Implementation**:
```bash
normalize_status_case() {
  tr '[:upper:]' '[:lower:]' <<< "$1"
}

# Usage in transformation
STATUS=$(normalize_status_case "$STATUS")
CONCLUSION=$(normalize_status_case "$CONCLUSION")
```

## Error Handling

### GraphQL Error Response

**Structure**:
```json
{
  "errors": [
    {
      "message": "Field 'checkSuites' doesn't exist on type 'Commit'",
      "locations": [{"line": 5, "column": 9}]
    }
  ]
}
```

**Detection**:
```bash
if echo "$response" | jq -e '.errors' >/dev/null 2>&1; then
  # GraphQL returned errors, fall back to REST
  return 1
fi
```

### Partial Response Handling

**Scenario**: Commit exists but has no check suites

**GraphQL Response**:
```json
{
  "oid": "abc123...",
  "checkSuites": {
    "nodes": []
  }
}
```

**Handling**: Treat as zero check runs, display `❔` icon

**Implementation**:
```bash
# In transformation jq:
$commit.checkSuites.nodes[]?   # The ? makes it optional
# If no nodes, no output lines for this SHA
# Aggregation logic detects 0 check runs → ❔ icon
```

### Timeout Handling

**Existing `run_with_timeout()` function** (lines 195-215):
```bash
run_with_timeout() {
  local timeout="$1"; shift
  timeout "$timeout" "$@" || {
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      echo "__TIMEOUT__"
    fi
    return $exit_code
  }
}
```

**GraphQL Timeout**:
```bash
GRAPHQL_RESPONSE=$(run_with_timeout "$API_TIMEOUT" gh api graphql -f query='...')
if [[ "$GRAPHQL_RESPONSE" == "__TIMEOUT__" ]]; then
  # Show ⏲ for all commits
  for i in $(seq 0 $((TOTAL-1))); do
    echo "⏲  ${LINE_MAP[$i]}" > "$TMPDIR/$i"
  done
fi
```

## Compatibility Matrix

| Feature | REST API | GraphQL | Notes |
|---------|----------|---------|-------|
| Commit limit | ✅ | ✅ | Both support `--limit` flag |
| Check run details | ✅ | ✅ | Identical `NAME\tSTATUS\tCONCLUSION` format after transformation |
| Timeout handling | ✅ | ✅ | Both use `run_with_timeout()` wrapper |
| Caching | ✅ | ✅ | Same cache key (SHA), same validation rules |
| Blocked queued detection | ✅ | ✅ | Logic ported to work with GraphQL response |
| `--checks` flag | ✅ | ✅ | Per-check details displayed identically |
| `--concurrency` flag | ✅ | N/A | GraphQL is single query (concurrency irrelevant) |
| GHES <3.4 | ✅ | ❌ (fallback) | GraphQL Checks API unavailable, auto-fallback to REST |
| Token scopes | `repo` | `repo` | Same scopes required |

## Testing Data Structures

**Test Fixtures**:
```bash
# Mock GraphQL response (success + failure + pending)
MOCK_GRAPHQL_RESPONSE='{
  "data": {
    "repository": {
      "ref": {
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "abc123",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"},
                          {"name": "test", "status": "IN_PROGRESS", "conclusion": null}
                        ]
                      }
                    }
                  ]
                }
              },
              {
                "oid": "def456",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {"name": "lint", "status": "COMPLETED", "conclusion": "FAILURE"}
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }
  }
}'

# Expected transformation output
EXPECTED_TSV="abc123	build	completed	success
abc123	test	in_progress
def456	lint	completed	failure"

# Expected aggregation
# abc123: 🕓 (pending test run)
# def456: ❌ (failed lint)
```

## Migration Strategy

**Phase 1**: Add GraphQL code path without removing REST code
- Both code paths coexist
- GraphQL is default, REST is fallback + opt-in via `--use-rest`

**Phase 2**: Monitor for issues
- Collect feedback on GraphQL performance
- Identify edge cases not handled
- Tune pagination limits if needed

**Phase 3** (future): Deprecate `--use-rest` flag
- After 6+ months of stable GraphQL operation
- Update documentation to reflect GraphQL-first approach
- Keep REST code as fallback for GHES compatibility

## Performance Metrics

**Key Metrics**:
1. API call count: Track GraphQL vs REST (target: 1 vs N)
2. Total execution time: Measure `time gh log-ci` (target: 50% reduction for 15+ commits)
3. Cache hit rate: Track `[cache hit]` debug messages (target: >80% for repeated runs)
4. Fallback rate: Track GraphQL errors requiring REST fallback (target: <5% on GitHub.com)

**Logging**:
```bash
if [[ "$CACHE_DEBUG" == "1" ]]; then
  echo "[graphql] query returned ${commit_count} commits in ${elapsed}s" >&2
  echo "[graphql] transformed to ${check_run_count} check runs" >&2
fi
```

## Future Enhancements

1. **Pagination**: Implement cursor-based pagination for repos with >100 check suites per commit
2. **Batch Caching**: Pass only uncached SHAs to GraphQL query (currently queries all commits)
3. **Rate Limit Awareness**: Parse `X-RateLimit-Remaining` header, warn user if <100 requests remaining
4. **Workflow Filtering**: Add flag to filter check runs by workflow name (e.g., `--workflow CI`)
5. **GraphQL-Only Mode**: Remove REST code after GHES <3.4 reaches end-of-life
