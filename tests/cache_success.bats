#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  # Mirror the script's branch resolution: in branch mode it prefers
  # origin/<branch> if the remote ref exists, else falls back to the local
  # branch. Deriving FULL_SHA/SHORT_SHA from this resolved ref ensures the
  # SHA we seed into the cache matches the SHA the script actually displays
  # (previously this hardcoded origin/master, which broke the test whenever
  # it ran on a non-master branch).
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    RESOLVED_REF="origin/$BRANCH"
  else
    RESOLVED_REF="$BRANCH"
  fi
  FULL_SHA="$(git rev-parse "$RESOLVED_REF")"
  SHORT_SHA="$(git rev-parse --short "$FULL_SHA")"
  # Ensure cache dir isolated for test
  export LOG_CI_CACHE_DIR="$(pwd)/.test-cache"
  rm -rf "$LOG_CI_CACHE_DIR" 2>/dev/null || true
  mkdir -p "$LOG_CI_CACHE_DIR"
}

# We simulate caching by running twice; second run should be faster and show cache hits (if debug enabled)
@test "uses seeded cache for success" {
  export LOG_CI_CACHE_DEBUG=1
  TS=$(date +%s)
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  OWNER="unknown"; REPO="unknown"
  if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; REPO="${REPO%.git}"
  fi
  CACHE_FILE="$LOG_CI_CACHE_DIR/${OWNER}_${REPO}_success.cache"
  echo -e "$FULL_SHA\t$TS" > "$CACHE_FILE"
  run "$SCRIPT" --limit 1 --branch "$BRANCH" --use-rest
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SHORT_SHA"* ]]
  [[ "$output" == *"[cache hit]"* ]]
}

@test "ignores cache when --no-cache flag is used" {
  export LOG_CI_CACHE_DEBUG=1
  TS=$(date +%s)
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  OWNER="unknown"; REPO="unknown"
  if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
    OWNER="${BASH_REMATCH[1]}"; REPO="${BASH_REMATCH[2]}"; REPO="${REPO%.git}"
  fi
  CACHE_FILE="$LOG_CI_CACHE_DIR/${OWNER}_${REPO}_success.cache"
  echo -e "$FULL_SHA\t$TS" > "$CACHE_FILE"
  run "$SCRIPT" --limit 1 --branch "$BRANCH" --no-cache --use-rest
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SHORT_SHA"* ]]
  [[ "$output" != *"[cache hit]"* ]]
}
