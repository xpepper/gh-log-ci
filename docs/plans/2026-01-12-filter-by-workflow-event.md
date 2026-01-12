# Filter by Workflow Event Type Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Exclude non-push workflow runs (like Dependabot's `event: "dynamic"`) from commit status aggregation to match GitHub's statusCheckRollup behavior.

**Architecture:** Replace time-based filtering with workflow event filtering. Query `workflowRun.event` via GraphQL, mark checks as excluded if event != "push", maintain display of excluded checks with `-C` flag.

**Tech Stack:** Bash, GraphQL API v4, jq for JSON processing, Bats for testing

---

## Problem Analysis

**Current Issue:** Time-based filtering doesn't work because scheduled/automated runs can execute within seconds of a commit.

**Example (commit `beb3b913a`):**
- Commit created: Jan 12 14:36:11
- Dependabot runs: Jan 12 14:36:29 (18 seconds later, within 4-hour threshold)
- Both Dependabot checks (success + failure) included in aggregation
- Result: Commit shows ❌ even though GitHub shows ✅

**GitHub's Behavior:**
- Uses `statusCheckRollup` which filters by `workflowRun.event == "push"`
- Excludes `event: "dynamic"` (Dependabot), `event: "schedule"`, etc.
- Only shows push-triggered checks in commit status

**Solution Approach:**
1. Query `workflowRun.event` for each check suite via GraphQL
2. Mark checks with `event != "push"` as EXCLUDED=1
3. Remove time-based filtering (superseded by event filtering)
4. Display excluded checks with `-C` flag (with event type annotation)

**TSV Format (updated):**
- Current: `SHA<TAB>NAME<TAB>STATUS<TAB>CONCLUSION<TAB>EXCLUDED`
- EXCLUDED now based on: `event != "push"` (not time difference)

---

## Task 1: Update GraphQL Queries to Include Workflow Event

**Files:**
- Modify: `gh-log-ci:265-293` (fetch_checks_graphql - batch query)
- Modify: `gh-log-ci:312-334` (fetch_checks_graphql_commit - single commit query)

**Step 1: Update batch GraphQL query to include workflow event**

Replace query in `fetch_checks_graphql` function (lines 265-293):

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
                  workflowRun {
                    event
                  }
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

**Step 2: Update single-commit GraphQL query to include workflow event**

Replace query in `fetch_checks_graphql_commit` function (lines 312-334):

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
            workflowRun {
              event
            }
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

**Step 3: Test GraphQL query manually**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
gh api graphql -f query='
query {
  repository(owner: "primait", name: "starsky") {
    object(expression: "beb3b913a") {
      ... on Commit {
        checkSuites(first: 5) {
          nodes {
            workflowRun {
              event
            }
            checkRuns(first: 3) {
              nodes {
                name
              }
            }
          }
        }
      }
    }
  }
}' --jq '.data.repository.object.checkSuites.nodes[] | {event: .workflowRun.event, checks: [.checkRuns.nodes[].name]}'
```

Expected: See events like "push", "dynamic", etc.

**Step 4: Commit**

```bash
git add gh-log-ci
git commit -m "feat: add workflowRun.event to GraphQL queries

- Include workflowRun.event in batch query
- Include workflowRun.event in single-commit query
- Preparation for event-based filtering"
```

---

## Task 2: Update Transformations to Filter by Event Type

**Files:**
- Modify: `gh-log-ci:67-68` (update environment variable)
- Modify: `gh-log-ci:342-364` (transform_graphql_response function)
- Modify: `gh-log-ci:368-388` (transform_graphql_response_commit function)

**Step 1: Remove time-based filtering environment variable**

Replace lines 67-68:

```bash
# Remove these lines:
TIME_FILTER_HOURS="${LOG_CI_TIME_FILTER_HOURS:-4}"
TIME_FILTER_SECONDS=$((TIME_FILTER_HOURS * 3600))
```

**Step 2: Update batch transformation to filter by event**

Replace `transform_graphql_response` function (lines 342-364):

```bash
# T015: Transform GraphQL nested response to flat TSV format with exclusion flag
transform_graphql_response() {
  local response="$1"

  # Transform nested GraphQL JSON to flat TSV with exclusion flag
  # Format: SHA<TAB>NAME<TAB>STATUS<TAB>CONCLUSION<TAB>EXCLUDED (0=push event, 1=non-push event)
  jq -r '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      # Mark as excluded if workflow event is not "push" (or if workflowRun is null)
      (.workflowRun.event // "unknown") as $event |
      (if $event != "push" then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$response" 2>/dev/null || true
}
```

**Step 3: Update single-commit transformation to filter by event**

Replace `transform_graphql_response_commit` function (lines 368-388):

```bash
# Transform single-commit GraphQL response to flat TSV format with exclusion flag
transform_graphql_response_commit() {
  local response="$1"

  jq -r '
    .data.repository.object as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      # Mark as excluded if workflow event is not "push" (or if workflowRun is null)
      (.workflowRun.event // "unknown") as $event |
      (if $event != "push" then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$response" 2>/dev/null || true
}
```

**Step 4: Test transformation logic**

```bash
cat > /tmp/test_event_filter.sh << 'EOF'
#!/bin/bash

test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","workflowRun":{"event":"push"},"checkRuns":{"nodes":[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]}},{"createdAt":"2025-01-12T10:00:10Z","workflowRun":{"event":"dynamic"},"checkRuns":{"nodes":[{"name":"Dependabot","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}]}}}}}}'

result=$(jq -r '
  .data.repository.ref.target.history.nodes[]? as $commit |
  $commit.oid as $sha |
  (
    $commit.checkSuites.nodes[]? |
    (.workflowRun.event // "unknown") as $event |
    (if $event != "push" then 1 else 0 end) as $excluded |
    .checkRuns.nodes[]? |
    [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
  ) |
  @tsv
' <<< "$test_data")

echo "Results:"
echo "$result"
echo ""

# CI (push event) should be marked 0
if echo "$result" | grep "CI" | grep -q $'\t0$'; then
  echo "✓ CI marked as included (push event)"
else
  echo "✗ CI NOT marked correctly"
  exit 1
fi

# Dependabot (dynamic event) should be marked 1
if echo "$result" | grep "Dependabot" | grep -q $'\t1$'; then
  echo "✓ Dependabot marked as excluded (dynamic event)"
else
  echo "✗ Dependabot NOT marked correctly"
  exit 1
fi

echo ""
echo "SUCCESS: Event-based filtering works correctly"
EOF
chmod +x /tmp/test_event_filter.sh
/tmp/test_event_filter.sh
```

Expected: SUCCESS message

**Step 5: Commit**

```bash
git add gh-log-ci
git commit -m "feat: replace time filtering with event-type filtering

- Remove TIME_FILTER_HOURS/SECONDS variables
- Filter by workflowRun.event (include only 'push' events)
- Update both transform functions to use event filtering
- Matches GitHub's statusCheckRollup behavior"
```

---

## Task 3: Update Aggregation Display for Event-Based Exclusion

**Files:**
- Modify: `gh-log-ci:579-592` (GraphQL mode aggregation loop)

**Step 1: Update excluded check display annotation**

Modify the display logic (around line 589):

```bash
# Skip excluded checks for status aggregation
if [[ "$EXCLUDED" == "1" ]]; then
  # Still display if -C flag is used
  if [[ "$SHOW_CHECKS" == "1" ]]; then
    ICON_RUN="🤖"  # Robot icon for non-push workflows
    SHORT_NAME="$NAME"
    [[ ${#SHORT_NAME} -gt 40 ]] && SHORT_NAME="${SHORT_NAME:0:37}..."
    DETAIL_OUTPUT+="    • $ICON_RUN $SHORT_NAME ($STATUS${CONCLUSION:+/$CONCLUSION}) [non-push]\n"
  fi
  continue  # Skip aggregation logic below
fi
```

**Step 2: Test manually**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
/Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci beb3b913a -C
```

Expected:
- Overall status: ✅ (not ❌)
- Dependabot checks shown with 🤖 icon and `[non-push]` label

**Step 3: Commit**

```bash
git add gh-log-ci
git commit -m "feat: update excluded check display for event filtering

- Change icon from ⏱ to 🤖 (robot for automated workflows)
- Change label from [excluded] to [non-push]
- Better communicates why check is excluded"
```

---

## Task 4: Update Help Documentation

**Files:**
- Modify: `gh-log-ci:50-54` (help text)

**Step 1: Remove LOG_CI_TIME_FILTER_HOURS from help**

Remove lines 50-54 (the time filter env var documentation)

**Step 2: Verify help text**

```bash
./gh-log-ci --help | grep -A 3 "Additional environment"
```

Expected: No mention of LOG_CI_TIME_FILTER_HOURS

**Step 3: Commit**

```bash
git add gh-log-ci
git commit -m "docs: remove LOG_CI_TIME_FILTER_HOURS from help

- Time-based filtering replaced with event-based filtering
- No user-configurable threshold needed"
```

---

## Task 5: Update Bats Tests for Event-Based Filtering

**Files:**
- Modify: `tests/time_filter.bats` → rename to `tests/event_filter.bats`
- Modify: `tests/graphql_batch.bats`

**Step 1: Rename and update time_filter.bats**

```bash
mv tests/time_filter.bats tests/event_filter.bats
```

Update content:

```bash
#!/usr/bin/env bats
# ABOUTME: Tests for event-based filtering of check suites
# ABOUTME: Ensures non-push workflows are excluded from commit status

@test "jq transformation marks non-push events as excluded" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","workflowRun":{"event":"push"},"checkRuns":{"nodes":[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]}},{"createdAt":"2025-01-12T10:00:10Z","workflowRun":{"event":"dynamic"},"checkRuns":{"nodes":[{"name":"Scheduled","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}]}}}}}}'

  result=$(jq -r '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      (.workflowRun.event // "unknown") as $event |
      (if $event != "push" then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$test_data")

  # CI (push event) should be marked 0 (included)
  echo "$result" | grep "CI" | grep -q $'\t0$'

  # Scheduled (dynamic event) should be marked 1 (excluded)
  echo "$result" | grep "Scheduled" | grep -q $'\t1$'
}

@test "jq transformation includes push event checks" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","workflowRun":{"event":"push"},"checkRuns":{"nodes":[{"name":"Deploy","status":"COMPLETED","conclusion":"SUCCESS"}]}}]}}]}}}}}}'

  result=$(jq -r '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      (.workflowRun.event // "unknown") as $event |
      (if $event != "push" then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$test_data")

  # Deploy (push event) should be marked 0 (included)
  echo "$result" | grep "Deploy" | grep -q $'\t0$'
}

@test "jq transformation handles null workflowRun (marks as excluded)" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","checkRuns":{"nodes":[{"name":"Legacy","status":"COMPLETED","conclusion":"SUCCESS"}]}}]}}]}}}}}}'

  result=$(jq -r '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      (.workflowRun.event // "unknown") as $event |
      (if $event != "push" then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$test_data")

  # Legacy (no workflowRun) should be marked 1 (excluded as unknown)
  echo "$result" | grep "Legacy" | grep -q $'\t1$'
}
```

**Step 2: Update graphql_batch.bats test**

Update the transformation test (around line 47):

```bash
@test "transformation of GraphQL response to TSV format" {
  # Test that transform_graphql_response() converts nested JSON to flat TSV with event-based exclusion

  local sample_json='{
    "data": {
      "repository": {
        "ref": {
          "target": {
            "history": {
              "nodes": [
                {
                  "oid": "abc123",
                  "committedDate": "2025-01-12T10:00:00Z",
                  "checkSuites": {
                    "nodes": [
                      {
                        "createdAt": "2025-01-12T10:00:05Z",
                        "workflowRun": {
                          "event": "push"
                        },
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
  }'

  # Expected TSV output: SHA<TAB>NAME<TAB>status<TAB>conclusion<TAB>excluded
  # Note: excluded=0 for push events
  expected="abc123	build	completed	success	0"

  source <(sed -n '/^transform_graphql_response()/,/^}/p' ./gh-log-ci)

  result=$(transform_graphql_response "$sample_json")
  [ "$result" = "$expected" ]
}
```

**Step 3: Run tests**

```bash
bats tests/event_filter.bats
bats tests/graphql_batch.bats
```

Expected: All tests pass

**Step 4: Commit**

```bash
git add tests/event_filter.bats tests/graphql_batch.bats
git rm tests/time_filter.bats
git commit -m "test: replace time-based tests with event-based tests

- Rename time_filter.bats to event_filter.bats
- Test event filtering (push vs dynamic vs null)
- Update graphql_batch.bats for event-based exclusion
- Add test for null workflowRun handling"
```

---

## Task 6: Manual Verification with Real Data

**Files:**
- N/A (manual testing)

**Step 1: Test with problematic commit beb3b913a**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
/Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci beb3b913a
```

Expected: Shows ✅ (not ❌)

**Step 2: Test with -C flag to see excluded checks**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
/Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci beb3b913a -C
```

Expected:
```
✅  beb3b913a - feat: enable entitlement api service on staging (#6590)
    • ✅ ci / rust / Detect changes (completed/success)
    • ✅ build / build / Cargo Build (completed/success)
    ...
    • 🤖 Dependabot (completed/success) [non-push]
    • 🤖 Dependabot (completed/failure) [non-push]
```

**Step 3: Test with other commits**

```bash
cd /Users/pietrodibello/Documents/workspace/prima/starsky
/Users/pietrodibello/Documents/workspace/gh-log-ci/gh-log-ci 9a8a6592 -C
```

Expected: Previous Dependabot failures now marked as `[non-push]` and excluded

---

## Task 7: Update Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`

**Step 1: Update README**

Replace "Time-Based Filtering" section with "Event-Based Filtering":

```markdown
### Event-Based Filtering

By default, `gh-log-ci` only includes checks from push-triggered workflows when computing the overall status icon. This matches GitHub's statusCheckRollup behavior and prevents automated workflows (like Dependabot, scheduled jobs) from incorrectly marking commits as failed.

GitHub associates check suites with the HEAD commit at run time, not the commit that triggered the suite. Without event filtering, automated workflows would affect the status of otherwise successful commits.

**Excluded checks are still displayed** when using the `-C` flag, marked with a 🤖 icon and `[non-push]` label for visibility.

This behavior matches what GitHub shows on the commit page - only push-triggered checks contribute to the overall commit status.
```

Remove `LOG_CI_TIME_FILTER_HOURS` from Configuration section.

Update Features table:
- Change: `Time-based filtering` → `Event-based filtering`
- Description: `Excludes non-push workflows from status aggregation while keeping them visible with -C`

**Step 2: Update CLAUDE.md**

Replace "Time-Based Filtering" section:

```markdown
**Event-Based Filtering (lines 342-388, 579-592):**
- Filters check suites by workflowRun.event type
- Only includes event="push" in status aggregation
- Adds EXCLUDED flag (0 or 1) as 5th TSV column based on event type
- Prevents automated workflows (Dependabot, scheduled) from affecting commit status
- Excluded checks displayed with `-C` flag, marked with 🤖 icon
- Applied in both `transform_graphql_response()` and `transform_graphql_response_commit()`
- REST mode marks all checks as EXCLUDED=0 (limitation: no workflow event available)
- Matches GitHub's statusCheckRollup behavior
```

**Step 3: Update AGENTS.md**

Replace "Time-Based Filtering" section:

```markdown
### Event-Based Filtering
- **Purpose**: Exclude non-push workflows from status aggregation while keeping them visible
- **Implementation**: Add EXCLUDED flag (5th TSV column) based on `workflowRun.event` field
- **Inclusion criteria**: Only `event == "push"` checks included in aggregation
- **Display behavior**: Excluded checks shown with 🤖 icon and `[non-push]` label when using `-C`
- **Aggregation**: Checks with EXCLUDED=1 skipped when computing overall status icon
- **GraphQL functions**: `transform_graphql_response()` and `transform_graphql_response_commit()`
- **REST mode limitation**: All checks marked EXCLUDED=0 (workflow event not available in REST API)
- **Matches GitHub**: Same filtering logic as GitHub's statusCheckRollup
```

Remove `LOG_CI_TIME_FILTER_HOURS` from environment variables.

Update Testing Structure:
- Change: `time_filter.bats` → `event_filter.bats`
- Description: Tests event-based filtering logic in jq transformations

**Step 4: Commit**

```bash
git add README.md CLAUDE.md AGENTS.md
git commit -m "docs: update to reflect event-based filtering

- Replace time-based filtering docs with event-based
- Remove LOG_CI_TIME_FILTER_HOURS references
- Explain event filtering matches GitHub behavior
- Update test file references"
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

Expected: All tests pass

**Step 3: Run full test**

```bash
make test
```

Expected: All tests pass

---

## Summary

This plan replaces time-based filtering with event-based filtering to match GitHub's statusCheckRollup behavior:

1. ✅ Queries `workflowRun.event` via GraphQL
2. ✅ Marks checks with `event != "push"` as EXCLUDED=1
3. ✅ Skips excluded checks during status aggregation
4. ✅ Displays excluded checks with `-C` flag (🤖 icon + `[non-push]` label)
5. ✅ Removes user-configurable threshold (no longer needed)
6. ✅ Matches GitHub's commit status page behavior exactly

**Key Benefits:**
- ✅ Commit `beb3b913a` now shows ✅ (matches GitHub)
- ✅ Dependabot/scheduled checks visible but don't fail commits
- ✅ Simpler implementation (no time calculations)
- ✅ More accurate (based on intent, not timing)
