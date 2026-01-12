# Filter Scheduled Check Suites Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Filter out check suites created long after commit time to exclude scheduled/periodic runs (like Dependabot) from commit status aggregation.

**Architecture:** Add `committedDate` and `createdAt` fields to GraphQL queries, filter check suites in jq transformation based on configurable time threshold (default 4 hours), ensuring only commit-relevant checks are displayed.

**Tech Stack:** Bash, GraphQL API v4, jq for JSON processing, Bats for testing

---

## Problem Analysis

**Issue:** GitHub associates check suites with the HEAD commit at the time the suite runs, not the commit that triggered it. This causes scheduled workflows (e.g., Dependabot running at 3 AM) to appear as failures for commits that are actually successful.

**Example:**
- Commit `9a8a659` created: Dec 15 14:37:44
- Push-triggered checks: Dec 15 14:37:46 (2 seconds later) ✅
- Post-deployment checks: Dec 15 17:14:18 (2.6 hours later) ✅
- Scheduled Dependabot: Dec 16 03:00:50 (12.4 hours later) ❌ (should be filtered)

**Solution:** Filter check suites by creation time - only include suites created within threshold after commit (default 4 hours = 14400 seconds).

---

## Task 1: Add Time Filtering to Batch GraphQL Query

**Files:**
- Modify: `gh-log-ci:255-298` (fetch_checks_graphql function)
- Modify: `gh-log-ci:339-353` (transform_graphql_response function)

**Step 1: Add environment variable for time threshold**

Add after line 68 (after other environment variable declarations):

```bash
TIME_FILTER_HOURS="${LOG_CI_TIME_FILTER_HOURS:-4}"
TIME_FILTER_SECONDS=$((TIME_FILTER_HOURS * 3600))
```

**Step 2: Update GraphQL query to include timestamps**

Modify the query in `fetch_checks_graphql` function (lines 262-289) to include `committedDate` and `createdAt`:

```graphql
query($owner: String!, $repo: String!, $branch: String!, $limit: Int!) {
  repository(owner: $owner, name: $repo) {
    ref(qualifiedName: $branch) {
      target {
        ... on Commit {
          history(first: $limit) {
            nodes {
              oid
              committedDate
              checkSuites(first: 100) {
                nodes {
                  createdAt
                  checkRuns(first: 100) {
                    nodes {
                      name
                      status
                      conclusion
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

**Step 3: Update transformation to filter by time**

Modify `transform_graphql_response` function (lines 339-353) to filter check suites:

```bash
transform_graphql_response() {
  local response="$1"
  local time_filter_seconds="${TIME_FILTER_SECONDS:-14400}"

  # Transform nested GraphQL JSON to flat TSV, filtering check suites by creation time
  jq -r --argjson filter_seconds "$time_filter_seconds" '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    $commit.committedDate as $commitDate |
    (
      $commit.checkSuites.nodes[]? |
      # Calculate time difference in seconds
      (((.createdAt | fromdateiso8601) - ($commitDate | fromdateiso8601)) | floor) as $timeDiff |
      # Only include check suites created within threshold
      select($timeDiff <= $filter_seconds) |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase)]
    ) |
    @tsv
  ' <<< "$response" 2>/dev/null || true
}
```

**Step 4: Test the transformation logic**

Create test file:

```bash
cat > /tmp/test_transform.sh << 'EOF'
#!/bin/bash
TIME_FILTER_SECONDS=14400

test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"9a8a659210c8f13071ab88add8c3e910b799b404","committedDate":"2025-12-15T14:37:44Z","checkSuites":{"nodes":[{"createdAt":"2025-12-15T14:37:46Z","checkRuns":{"nodes":[{"name":"ci / build","status":"COMPLETED","conclusion":"SUCCESS"}]}},{"createdAt":"2025-12-16T03:00:50Z","checkRuns":{"nodes":[{"name":"Dependabot","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}]}}}}}'

result=$(jq -r --argjson filter_seconds "$TIME_FILTER_SECONDS" '
  .data.repository.ref.target.history.nodes[]? as $commit |
  $commit.oid as $sha |
  $commit.committedDate as $commitDate |
  (
    $commit.checkSuites.nodes[]? |
    (((.createdAt | fromdateiso8601) - ($commitDate | fromdateiso8601)) | floor) as $timeDiff |
    select($timeDiff <= $filter_seconds) |
    .checkRuns.nodes[]? |
    [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $timeDiff]
  ) |
  @tsv
' <<< "$test_data")

echo "Filtered results:"
echo "$result"

if echo "$result" | grep -q "Dependabot"; then
  echo "ERROR: Dependabot should be filtered out"
  exit 1
fi

if ! echo "$result" | grep -q "ci / build"; then
  echo "ERROR: ci / build should be included"
  exit 1
fi

echo "SUCCESS: Filtering works correctly"
EOF
chmod +x /tmp/test_transform.sh
/tmp/test_transform.sh
```

Expected output:
```
Filtered results:
9a8a659210c8f13071ab88add8c3e910b799b404	ci / build	completed	success	2
SUCCESS: Filtering works correctly
```

**Step 5: Run the test script**

```bash
/tmp/test_transform.sh
```

Expected: SUCCESS message, no errors

**Step 6: Commit batch query changes**

```bash
git add gh-log-ci
git commit -m "feat: add time-based filtering to batch GraphQL query

- Add LOG_CI_TIME_FILTER_HOURS env var (default 4 hours)
- Include committedDate and createdAt in GraphQL query
- Filter check suites created beyond threshold
- Prevents scheduled runs from affecting commit status"
```

---

## Task 2: Add Time Filtering to Single Commit GraphQL Query

**Files:**
- Modify: `gh-log-ci:301-336` (fetch_checks_graphql_commit function)
- Modify: `gh-log-ci:355-369` (transform_graphql_response_commit function)

**Step 1: Update single-commit GraphQL query**

Modify the query in `fetch_checks_graphql_commit` function (lines 307-328) to include timestamps:

```graphql
query($owner: String!, $repo: String!, $sha: String!) {
  repository(owner: $owner, name: $repo) {
    object(expression: $sha) {
      ... on Commit {
        oid
        committedDate
        checkSuites(first: 100) {
          nodes {
            createdAt
            checkRuns(first: 100) {
              nodes {
                name
                status
                conclusion
              }
            }
          }
        }
      }
    }
  }
}
```

**Step 2: Update single-commit transformation to filter by time**

Modify `transform_graphql_response_commit` function (lines 355-369):

```bash
transform_graphql_response_commit() {
  local response="$1"
  local time_filter_seconds="${TIME_FILTER_SECONDS:-14400}"

  jq -r --argjson filter_seconds "$time_filter_seconds" '
    .data.repository.object as $commit |
    $commit.oid as $sha |
    $commit.committedDate as $commitDate |
    (
      $commit.checkSuites.nodes[]? |
      # Calculate time difference in seconds
      (((.createdAt | fromdateiso8601) - ($commitDate | fromdateiso8601)) | floor) as $timeDiff |
      # Only include check suites created within threshold
      select($timeDiff <= $filter_seconds) |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase)]
    ) |
    @tsv
  ' <<< "$response" 2>/dev/null || true
}
```

**Step 3: Test single-commit transformation**

```bash
cat > /tmp/test_transform_commit.sh << 'EOF'
#!/bin/bash
TIME_FILTER_SECONDS=14400

test_data='{"data":{"repository":{"object":{"oid":"9a8a659210c8f13071ab88add8c3e910b799b404","committedDate":"2025-12-15T14:37:44Z","checkSuites":{"nodes":[{"createdAt":"2025-12-15T14:37:46Z","checkRuns":{"nodes":[{"name":"ci / build","status":"COMPLETED","conclusion":"SUCCESS"}]}},{"createdAt":"2025-12-16T03:00:50Z","checkRuns":{"nodes":[{"name":"Dependabot","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}}}}'

result=$(jq -r --argjson filter_seconds "$TIME_FILTER_SECONDS" '
  .data.repository.object as $commit |
  $commit.oid as $sha |
  $commit.committedDate as $commitDate |
  (
    $commit.checkSuites.nodes[]? |
    (((.createdAt | fromdateiso8601) - ($commitDate | fromdateiso8601)) | floor) as $timeDiff |
    select($timeDiff <= $filter_seconds) |
    .checkRuns.nodes[]? |
    [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase)]
  ) |
  @tsv
' <<< "$test_data")

echo "Filtered results:"
echo "$result"

if echo "$result" | grep -q "Dependabot"; then
  echo "ERROR: Dependabot should be filtered out"
  exit 1
fi

if ! echo "$result" | grep -q "ci / build"; then
  echo "ERROR: ci / build should be included"
  exit 1
fi

echo "SUCCESS: Single-commit filtering works correctly"
EOF
chmod +x /tmp/test_transform_commit.sh
/tmp/test_transform_commit.sh
```

Expected: SUCCESS message

**Step 4: Run the test**

```bash
/tmp/test_transform_commit.sh
```

Expected: SUCCESS message, no errors

**Step 5: Commit single-commit query changes**

```bash
git add gh-log-ci
git commit -m "feat: add time-based filtering to single-commit GraphQL query

- Include committedDate and createdAt in query
- Filter check suites in transform_graphql_response_commit
- Consistent filtering logic across batch and single modes"
```

---

## Task 3: Add Help Documentation for New Feature

**Files:**
- Modify: `gh-log-ci:120-154` (help text)

**Step 1: Add LOG_CI_TIME_FILTER_HOURS to environment variables section**

Add after line 143 (in the environment variables section):

```
  LOG_CI_TIME_FILTER_HOURS
      Maximum hours between commit and check suite creation (default: 4).
      Check suites created after this threshold are filtered out.
      Prevents scheduled workflows from affecting commit status.
```

**Step 2: Verify help text displays correctly**

```bash
./gh-log-ci --help | grep -A 3 "LOG_CI_TIME_FILTER_HOURS"
```

Expected output:
```
  LOG_CI_TIME_FILTER_HOURS
      Maximum hours between commit and check suite creation (default: 4).
      Check suites created after this threshold are filtered out.
      Prevents scheduled workflows from affecting commit status.
```

**Step 3: Commit documentation**

```bash
git add gh-log-ci
git commit -m "docs: document LOG_CI_TIME_FILTER_HOURS environment variable"
```

---

## Task 4: Write Test for Time Filtering

**Files:**
- Create: `tests/time_filter.bats`

**Step 1: Write failing test for time filtering**

```bash
cat > tests/time_filter.bats << 'EOF'
#!/usr/bin/env bats

# ABOUTME: Tests for time-based filtering of check suites
# ABOUTME: Ensures scheduled runs are excluded from commit status

setup() {
  # Create mock gh that returns check data with old and new suites
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"

  cat > "$BATS_TEST_DIRNAME/mocks/gh" << 'GHEOF'
#!/bin/bash
if [[ "$1" == "api" && "$2" == "graphql" ]]; then
  # Return data with one recent suite and one old suite
  cat << 'JSONEOF'
{"data":{"repository":{"object":{"oid":"abc1234","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","checkRuns":{"nodes":[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]}},{"createdAt":"2025-01-13T03:00:00Z","checkRuns":{"nodes":[{"name":"Scheduled Job","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}}}}
JSONEOF
  exit 0
fi
exec /usr/bin/gh "$@"
GHEOF
  chmod +x "$BATS_TEST_DIRNAME/mocks/gh"
}

teardown() {
  rm -rf "$BATS_TEST_DIRNAME/mocks"
}

@test "filters out check suites created after time threshold" {
  run bash -c 'cd $(git rev-parse --show-toplevel) && LOG_CI_TIME_FILTER_HOURS=4 ./gh-log-ci abc1234 -C'

  # Should include recent CI check
  [[ "$output" =~ "CI" ]]

  # Should NOT include scheduled job from 17 hours later
  ! [[ "$output" =~ "Scheduled Job" ]]
}

@test "includes check suites within time threshold" {
  run bash -c 'cd $(git rev-parse --show-toplevel) && LOG_CI_TIME_FILTER_HOURS=24 ./gh-log-ci abc1234 -C'

  # With 24 hour threshold, should include both
  [[ "$output" =~ "CI" ]]
  [[ "$output" =~ "Scheduled Job" ]]
}

@test "uses default 4 hour threshold when env var not set" {
  run bash -c 'cd $(git rev-parse --show-toplevel) && unset LOG_CI_TIME_FILTER_HOURS && ./gh-log-ci abc1234 -C'

  # Default should filter 17-hour-old suite
  [[ "$output" =~ "CI" ]]
  ! [[ "$output" =~ "Scheduled Job" ]]
}
EOF
```

**Step 2: Run test to verify it fails**

```bash
bats tests/time_filter.bats
```

Expected: Tests should FAIL because filtering is not yet implemented in the script

**Step 3: Verify tests pass after implementation**

```bash
bats tests/time_filter.bats
```

Expected: All tests PASS

**Step 4: Commit test**

```bash
git add tests/time_filter.bats
git commit -m "test: add time-based filtering tests

- Test filtering with default 4 hour threshold
- Test custom threshold via LOG_CI_TIME_FILTER_HOURS
- Verify scheduled checks are excluded"
```

---

## Task 5: Manual Verification with Real Data

**Files:**
- N/A (manual testing)

**Step 1: Test with the problematic commit**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
/Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci 9a8a6592 -C
```

Expected output: Should show ✅ for overall status, Dependabot check should NOT appear

**Step 2: Test with relaxed threshold to include Dependabot**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
LOG_CI_TIME_FILTER_HOURS=24 /Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci 9a8a6592 -C
```

Expected output: Should show ❌ for overall status, Dependabot check SHOULD appear

**Step 3: Test with multiple commits in batch mode**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
/Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci --limit 5
```

Expected output: Should show commit log with accurate status icons, no scheduled checks

**Step 4: Document verification results**

Create verification notes in git commit message documenting the before/after behavior

---

## Task 6: Update README with New Feature

**Files:**
- Modify: `README.md` (environment variables section)

**Step 1: Add LOG_CI_TIME_FILTER_HOURS to environment variables table**

Find the environment variables section and add:

```markdown
| `LOG_CI_TIME_FILTER_HOURS` | `4` | Maximum hours between commit and check suite creation. Check suites created after this threshold are filtered out to exclude scheduled/periodic workflows. |
```

**Step 2: Add explanation in behavior section**

Add a new section after the "Caching" section:

```markdown
### Time-Based Filtering

By default, gh-log-ci only shows check suites created within 4 hours of the commit. This prevents scheduled workflows (like Dependabot running at 3 AM) from incorrectly marking commits as failed when they were actually successful.

GitHub associates check suites with the HEAD commit at the time the suite runs, not the commit that triggered the suite. Without time filtering, scheduled workflows would appear as failures for otherwise successful commits.

Configure the threshold with `LOG_CI_TIME_FILTER_HOURS`:

```bash
# Include checks created within 1 hour of commit (strict)
LOG_CI_TIME_FILTER_HOURS=1 gh log-ci

# Include checks created within 24 hours (permissive)
LOG_CI_TIME_FILTER_HOURS=24 gh log-ci

# Disable filtering (include all check suites regardless of timing)
LOG_CI_TIME_FILTER_HOURS=999999 gh log-ci
```
```

**Step 3: Verify README renders correctly**

```bash
# Preview README locally or push to see rendering
head -50 README.md
```

**Step 4: Commit README updates**

```bash
git add README.md
git commit -m "docs: document time-based filtering feature

- Add LOG_CI_TIME_FILTER_HOURS to env vars table
- Explain why time filtering is needed
- Provide usage examples for different thresholds"
```

---

## Task 7: Update CLAUDE.md and AGENTS.md

**Files:**
- Modify: `CLAUDE.md` (add time filtering to architecture overview)
- Modify: `AGENTS.md` (add time filtering to architecture section)

**Step 1: Update CLAUDE.md architecture section**

Add to the "Key Design Patterns" section:

```markdown
**Time-Based Filtering (lines 68-69, 339-368):**
- Filters check suites by creation time relative to commit time
- Default threshold: 4 hours after commit
- Prevents scheduled/periodic workflows from affecting commit status
- Configurable via `LOG_CI_TIME_FILTER_HOURS` environment variable
- Applied in both `transform_graphql_response()` and `transform_graphql_response_commit()`
```

**Step 2: Update AGENTS.md architecture section**

Add to the "Key Components" section:

```markdown
### Time Filtering
- **Purpose**: Exclude scheduled workflows that run against HEAD commit
- **Implementation**: Filter check suites by `createdAt` vs `committedDate` difference
- **Default threshold**: 4 hours (14400 seconds)
- **Configuration**: `LOG_CI_TIME_FILTER_HOURS` environment variable
- **Applied in**: `transform_graphql_response()` (lines 339-353) and `transform_graphql_response_commit()` (lines 355-369)
```

**Step 3: Add to environment variables list**

In AGENTS.md, add to the "Environment Variables" section:

```markdown
- `LOG_CI_TIME_FILTER_HOURS`: Maximum hours between commit and check suite creation (default: 4)
```

**Step 4: Commit documentation updates**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs: update architecture docs with time filtering

- Document time-based filtering in key design patterns
- Add LOG_CI_TIME_FILTER_HOURS to environment variables
- Explain purpose and implementation details"
```

---

## Task 8: Run Full Test Suite

**Files:**
- N/A (test execution)

**Step 1: Run shellcheck**

```bash
make shellcheck
```

Expected: No errors

**Step 2: Run all bats tests**

```bash
make bats
```

Expected: All tests pass, including new time_filter.bats

**Step 3: Run full test suite**

```bash
make test
```

Expected: All tests pass

**Step 4: Verify no regressions**

```bash
# Test various scenarios
./gh-log-ci --help
./gh-log-ci --limit 3
./gh-log-ci $(git rev-parse HEAD)
./gh-log-ci --watch --interval 5  # Let it run for one iteration, then Ctrl+C
```

Expected: All commands work as expected, no errors

---

## Summary

This plan implements time-based filtering to solve the issue where scheduled workflows (like Dependabot) incorrectly mark commits as failed. The solution:

1. ✅ Adds `committedDate` and `createdAt` to GraphQL queries
2. ✅ Filters check suites in jq transformation using configurable threshold
3. ✅ Applies filtering to both batch and single-commit modes
4. ✅ Defaults to 4-hour threshold (configurable via `LOG_CI_TIME_FILTER_HOURS`)
5. ✅ Includes comprehensive tests and documentation
6. ✅ Maintains backward compatibility (default behavior improves accuracy)

**Time estimate per task:**
- Task 1: ~15 minutes (GraphQL query + transformation + testing)
- Task 2: ~10 minutes (single-commit query + transformation)
- Task 3: ~5 minutes (help text)
- Task 4: ~10 minutes (bats tests)
- Task 5: ~10 minutes (manual verification)
- Task 6: ~5 minutes (README)
- Task 7: ~5 minutes (architecture docs)
- Task 8: ~5 minutes (full test suite)

**Total: ~65 minutes**
