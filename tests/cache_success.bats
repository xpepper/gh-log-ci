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
@test "uses seeded cache for success" {
  export LOG_CI_CACHE_DEBUG=1
  FULL_SHA=$(git rev-parse HEAD)
  SHORT_SHA=$(git rev-parse --short HEAD)
  TS=$(date +%s)
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  OWNER="unknown"; REPO="unknown"
  if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; REPO="${REPO%.git}"
  fi
  CACHE_FILE="$LOG_CI_CACHE_DIR/${OWNER}_${REPO}_success.cache"
  echo -e "$FULL_SHA\t$TS" > "$CACHE_FILE"
  run "$SCRIPT" --limit 1 --branch "$BRANCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SHORT_SHA"* ]]
}
