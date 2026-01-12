#!/usr/bin/env bats
# ABOUTME: Tests for event-based filtering of check suites
# ABOUTME: Ensures non-push workflows are excluded from commit status

setup() {
  # Event-based filtering uses workflowRun.event field
  # Tests will verify exclusion logic in jq transformations
  export LOG_CI_NO_SPINNER=1
}

@test "jq transformation marks non-push events as excluded" {
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

  # CI (push event) should be marked 0 (included)
  echo "$result" | grep "CI" | grep -q $'\t0$'

  # Dependabot (dynamic event) should be marked 1 (excluded)
  echo "$result" | grep "Dependabot" | grep -q $'\t1$'
}

@test "jq transformation includes push events regardless of timing" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-13T03:00:00Z","workflowRun":{"event":"push"},"checkRuns":{"nodes":[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]}}]}}]}}}}}}'

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

  # CI (push event, even 17 hours later) should be marked 0 (included)
  echo "$result" | grep "CI" | grep -q $'\t0$'
}

@test "jq transformation handles null workflowRun event" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","checkRuns":{"nodes":[{"name":"Manual","status":"COMPLETED","conclusion":"SUCCESS"}]}}]}}]}}}}}}'

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

  # Manual (null event) should be marked 1 (excluded)
  echo "$result" | grep "Manual" | grep -q $'\t1$'
}
