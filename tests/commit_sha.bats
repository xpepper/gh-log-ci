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

@test "fails on invalid commit SHA" {
  run "$SCRIPT" "invalidsha123" --use-rest
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error"* ]]
}

@test "shows single commit without extra commits" {
  SHA=$(git rev-parse HEAD~5)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  # Count status lines (lines starting with emoji)
  STATUS_LINES=$(echo "$output" | grep -E '^[✅❌🕓🚫❔⏲🔁]' | wc -l)
  [ "$STATUS_LINES" -eq 1 ]
}
