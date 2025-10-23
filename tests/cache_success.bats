#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  # Ensure cache dir isolated for test
  export LOG_CI_CACHE_DIR="$(pwd)/.test-cache"
  rm -rf "$LOG_CI_CACHE_DIR" 2>/dev/null || true
  mkdir -p "$LOG_CI_CACHE_DIR"
}

# We simulate caching by running twice; second run should be faster and show cache hits (if debug enabled)
@test "caches successful commits" {
  export LOG_CI_CACHE_DEBUG=1
  export LOG_CI_WATCH_ONCE=1
  CACHE_FILE=$(echo "$LOG_CI_CACHE_DIR"/*.cache)
  # Ensure no cache file yet
  [ ! -f "$CACHE_FILE" ] || rm -f "$CACHE_FILE"
  run "$SCRIPT" --limit 1 --branch "$BRANCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  # Cache file should now exist and contain 1 line
  CACHE_FILE=$(echo "$LOG_CI_CACHE_DIR"/*.cache)
  [ -f "$CACHE_FILE" ]
  lines_first=$(wc -l < "$CACHE_FILE")
  [ "$lines_first" -ge 1 ]

  # Second run should produce same success; optionally show cache hit
  run "$SCRIPT" --limit 1 --branch "$BRANCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅"* ]]
  lines_second=$(wc -l < "$CACHE_FILE")
  [ "$lines_second" -eq "$lines_first" ]
}
