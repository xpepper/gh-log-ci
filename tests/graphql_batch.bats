#!/usr/bin/env bats

# Tests for GraphQL batch query functionality
# These tests verify GraphQL query construction, response transformation,
# fallback behavior, and output parity with REST API

setup() {
  # Test setup - can be used to mock gh CLI responses if needed
  export LOG_CI_CACHE_DEBUG=0
  export LOG_CI_NO_SPINNER=1
}

teardown() {
  # Test cleanup
  unset LOG_CI_CACHE_DEBUG
  unset LOG_CI_NO_SPINNER
}

# ==============================================================================
# User Story 1: Fast Status Display with Reduced API Calls (T009-T013)
# ==============================================================================

@test "GraphQL query construction with limit 5" {
  # Verify that when --limit 5 is used, the GraphQL query would include first: 5
  # This is a basic test to ensure the limit parameter is properly passed

  # For now, we test that the flag is accepted and help shows the option
  run ./gh-log-ci --help
  [ "$status" -eq 0 ]
  [[ "$output" =~ "--limit" ]]

  # TODO T014: Once fetch_checks_graphql() is implemented, test actual query construction
}

@test "single GraphQL call made vs multiple REST calls" {
  skip "Test to be implemented - T010"
  # TODO: Mock gh api calls and count GraphQL vs REST invocations
  # Expected: GraphQL = 1 call, REST = N calls
}

@test "GraphQL output matches REST output (parity test)" {
  skip "Test to be implemented - T011"
  # TODO: Run both modes with identical input, compare outputs
  # Expected: Outputs are identical
}

@test "transformation of GraphQL response to TSV format" {
  # Test that transform_graphql_response() converts nested JSON to flat TSV with exclusion flag

  # Sample GraphQL response with workflowRun.event
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
  # Note: status and conclusion should be lowercase, excluded=0 for push events
  expected="abc123	build	completed	success	0"

  # Source the script to load the function
  # Extract just the function definition to avoid running the whole script
  source <(sed -n '/^transform_graphql_response()/,/^}/p' ./gh-log-ci)

  result=$(transform_graphql_response "$sample_json")
  [ "$result" = "$expected" ]
}

# ==============================================================================
# User Story 2: Fallback to REST API (T031-T034)
# ==============================================================================

# ==============================================================================
# User Story 2: REST Mode Option for Compatibility (T031-T034)
# ==============================================================================

@test "--use-rest flag bypasses GraphQL" {
  # T031: Verify that --use-rest flag prevents GraphQL query
  # We test this by checking that no GraphQL-specific debug messages appear

  export LOG_CI_CACHE_DEBUG=1
  BRANCH=$(git rev-parse --abbrev-ref HEAD)

  run ./gh-log-ci --limit 1 --branch "$BRANCH" --use-rest --no-cache

  [ "$status" -eq 0 ]
  # Should NOT see GraphQL debug messages
  ! [[ "$output" =~ "\[GraphQL\]" ]]
}

@test "LOG_CI_FORCE_REST=1 bypasses GraphQL" {
  # T032: Verify that LOG_CI_FORCE_REST environment variable prevents GraphQL

  export LOG_CI_FORCE_REST=1
  export LOG_CI_CACHE_DEBUG=1
  BRANCH=$(git rev-parse --abbrev-ref HEAD)

  run ./gh-log-ci --limit 1 --branch "$BRANCH" --no-cache

  [ "$status" -eq 0 ]
  # Should NOT see GraphQL debug messages
  ! [[ "$output" =~ "\[GraphQL\]" ]]
}

@test "--use-rest works with --concurrency flag" {
  # T033: Verify that --use-rest works with custom concurrency

  BRANCH=$(git rev-parse --abbrev-ref HEAD)

  run ./gh-log-ci --limit 5 --branch "$BRANCH" --use-rest --concurrency 2 --no-cache

  [ "$status" -eq 0 ]
  # Should display commit info (check for status icons)
  [[ "$output" =~ ✅|❌|🕓 ]]
}

@test "--use-rest flag appears in help text" {
  # T034: Verify help documentation includes --use-rest flag

  run ./gh-log-ci --help

  [ "$status" -eq 0 ]
  [[ "$output" =~ "--use-rest" ]]
  [[ "$output" =~ "REST API" ]]
}

# ==============================================================================
# Removed: Automatic Fallback Tests (no longer applicable after refactor)
# ==============================================================================

@test "fallback on GraphQL error response" {
  skip "Test removed - automatic fallback no longer exists (use --use-rest instead)"
}

@test "fallback on GraphQL timeout" {
  skip "Test removed - automatic fallback no longer exists (use --use-rest instead)"
}

@test "fallback on missing GraphQL fields (GHES <3.4 simulation)" {
  skip "Test removed - automatic fallback no longer exists (use --use-rest instead)"
}

