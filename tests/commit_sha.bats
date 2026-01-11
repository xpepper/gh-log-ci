#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
}

@test "accepts valid commit SHA" {
  # Get a real commit SHA from current repo
  SHA=$(git rev-parse HEAD~1)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  # Should contain the SHA
  [[ "$output" == *"${SHA:0:7}"* ]]
  # Should NOT contain warning about remote branch
  [[ "$output" != *"Warning: Remote branch"* ]]
  # Should show exactly 1 status line (count lines starting with emoji)
  STATUS_LINES=$(echo "$output" | grep -c -E '^[✅❌🕓🚫❔⏲🔁]')
  [ "$STATUS_LINES" -eq 1 ]
}

@test "accepts short commit SHA (7 chars)" {
  SHA=$(git rev-parse --short=7 HEAD~1)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  [[ "$output" == *"$SHA"* ]]
  [[ "$output" != *"Warning:"* ]]
}

@test "treats invalid SHA as branch name (expected to fail)" {
  # Invalid SHA-like strings are treated as branch names and will fail
  # when the branch doesn't exist (not an error per spec)
  run "$SCRIPT" "invalidsha123" --use-rest
  [ "$status" -eq 1 ]
  # Will fail with git error, not explicit SHA validation error
}

@test "shows single commit without extra commits" {
  SHA=$(git rev-parse HEAD~5)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  # Count status lines (lines starting with emoji)
  STATUS_LINES=$(echo "$output" | grep -E '^[✅❌🕓🚫❔⏲🔁]' | wc -l)
  [ "$STATUS_LINES" -eq 1 ]
}

@test "does not emit remote branch warning for commit SHA" {
  SHA=$(git rev-parse HEAD~1)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  # Critical: no warning should appear
  [[ "$output" != *"Warning: Remote branch"* ]]
  [[ "$output" != *"not found on origin"* ]]
}

@test "works with GraphQL mode (without --use-rest)" {
  # Detect which default branch exists (master or main)
  DEFAULT_BRANCH=""
  if git rev-parse origin/master >/dev/null 2>&1; then
    DEFAULT_BRANCH="origin/master"
  elif git rev-parse origin/main >/dev/null 2>&1; then
    DEFAULT_BRANCH="origin/main"
  else
    skip "No default remote branch (master or main) found"
  fi

  SHA=$(git rev-parse "$DEFAULT_BRANCH")
  run "$SCRIPT" "$SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${SHA:0:7}"* ]]
  [[ "$output" != *"Warning:"* ]]
  # Should show exactly 1 status line
  STATUS_LINES=$(echo "$output" | grep -E '^[✅❌🕓🚫❔⏲🔁]' | wc -l)
  [ "$STATUS_LINES" -eq 1 ]
}

@test "help shows commit SHA usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  # Usage line should show both branch and commit-sha options
  [[ "$output" == *"<branch>|<commit-sha>"* ]]
  # Should have a dedicated section explaining commit SHA mode
  [[ "$output" == *"Commit SHA mode:"* ]]
  # Examples should show commit SHA usage
  [[ "$output" == *"gh log-ci 7b60fc9"* ]]
}
