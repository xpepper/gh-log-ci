#!/usr/bin/env bats
# ABOUTME: Tests for time-based filtering of check suites
# ABOUTME: Ensures scheduled runs are excluded from commit status

setup() {
  export LOG_CI_TIME_FILTER_HOURS=4
  # Tests will verify exclusion logic in jq transformations
}

@test "jq transformation marks late checks as excluded" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:00:05Z","checkRuns":{"nodes":[{"name":"CI","status":"COMPLETED","conclusion":"SUCCESS"}]}},{"createdAt":"2025-01-13T03:00:00Z","checkRuns":{"nodes":[{"name":"Scheduled","status":"COMPLETED","conclusion":"FAILURE"}]}}]}}]}}}}}}'

  result=$(jq -r --argjson filter_seconds 14400 '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    $commit.committedDate as $commitDate |
    (
      $commit.checkSuites.nodes[]? |
      (((.createdAt | fromdateiso8601) - ($commitDate | fromdateiso8601)) | floor) as $timeDiff |
      (if $timeDiff > $filter_seconds then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$test_data")

  # CI should be marked 0 (included)
  echo "$result" | grep "CI" | grep -q $'\t0$'

  # Scheduled should be marked 1 (excluded)
  echo "$result" | grep "Scheduled" | grep -q $'\t1$'
}

@test "jq transformation includes checks within threshold" {
  test_data='{"data":{"repository":{"ref":{"target":{"history":{"nodes":[{"oid":"abc123","committedDate":"2025-01-12T10:00:00Z","checkSuites":{"nodes":[{"createdAt":"2025-01-12T10:30:00Z","checkRuns":{"nodes":[{"name":"Deploy","status":"COMPLETED","conclusion":"SUCCESS"}]}}]}}]}}}}}}'

  result=$(jq -r --argjson filter_seconds 14400 '
    .data.repository.ref.target.history.nodes[]? as $commit |
    $commit.oid as $sha |
    $commit.committedDate as $commitDate |
    (
      $commit.checkSuites.nodes[]? |
      (((.createdAt | fromdateiso8601) - ($commitDate | fromdateiso8601)) | floor) as $timeDiff |
      (if $timeDiff > $filter_seconds then 1 else 0 end) as $excluded |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase), $excluded]
    ) |
    @tsv
  ' <<< "$test_data")

  # Deploy (30 min later) should be marked 0 (included)
  echo "$result" | grep "Deploy" | grep -q $'\t0$'
}
