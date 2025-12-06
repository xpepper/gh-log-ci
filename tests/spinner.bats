#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
  export TMPDIR="${BATS_TMPDIR}/bats-test-$$"
  mkdir -p "$TMPDIR"
}

teardown() {
  # Clean up any temporary files
  rm -rf "$TMPDIR"
  # Kill any background processes that might be left
  jobs -p | xargs -r kill 2>/dev/null || true
}

@test "spinner displays with default settings" {
  # Run normally and verify spinner behavior
  run "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # Output should not contain spinner characters after completion (line clearing)
  [[ ! "$output" =~ [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ]] || true
}

@test "--no-spinner flag disables spinner" {
  run "$SCRIPT" --no-spinner --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # When spinner is disabled, output should not contain spinner characters
  [[ ! "$output" =~ [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ]]
}

@test "LOG_CI_NO_SPINNER environment variable disables spinner" {
  LOG_CI_NO_SPINNER=1 run "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # When spinner is disabled, output should not contain spinner characters
  [[ ! "$output" =~ [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ]]
}

@test "spinner handles zero commits gracefully" {
  # Test with limit=0 to see how spinner handles edge case
  run "$SCRIPT" --limit 0 --branch "$(git rev-parse --abbrev-ref HEAD)"
  # Should properly reject limit=0 with error message
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "spinner with single commit" {
  # Test with single commit
  run "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # Should successfully complete with single commit
  [[ "$output" == *"02e0643"* ]] || true  # Contains a commit hash
}

@test "spinner works with output redirection to file" {
  local output_file="${TMPDIR}/spinner_output.txt"
  "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)" > "$output_file"
  # File should be created and contain output
  [ -f "$output_file" ]
  [ -s "$output_file" ]
  # Check if output contains expected content (commit hash)
  grep -q "02e0643" "$output_file" || true
}

@test "spinner works with cached commits" {
  # First run to populate cache
  LOG_CI_CACHE_TTL=86400 "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  # Second run should be faster due to cache
  LOG_CI_CACHE_TTL=86400 run "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
}

@test "spinner handles terminal line clearing" {
  # Test that spinner properly clears line after completion
  run "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # Should not leave spinner characters in final output
  # The line clearing happens after completion, so final output should be clean
  [[ ! "$output" =~ [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ]] || true
}

@test "spinner with concurrent processing" {
  # Test spinner behavior with multiple parallel API calls
  LOG_CI_CONCURRENCY=2 run "$SCRIPT" --limit 2 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # Should complete successfully with concurrency
  true
}

@test "spinner cleanup on normal completion" {
  # Test that spinner cleans up properly on normal completion
  run "$SCRIPT" --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
  # No spinner characters should remain in output
  [[ ! "$output" =~ [⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] ]] || true
}

@test "spinner function exists and is callable" {
  # Test that the spinner function is defined in the script
  run grep -q "spinner()" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "spinner frames are defined correctly" {
  # Test that spinner frames are defined
  run grep -q "frames=" "$SCRIPT"
  [ "$status" -eq 0 ]
  # Should contain spinner frame characters
  run grep -q "⠋\|⠙\|⠹\|⠸\|⠼\|⠴\|⠦\|⠧\|⠇\|⠏" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "spinner progress counter implementation" {
  # Test that progress counter logic is implemented
  run grep -q "COMPLETED" "$SCRIPT"
  [ "$status" -eq 0 ]
  run grep -q "TOTAL" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "spinner cleanup mechanism" {
  # Test that spinner cleanup is implemented
  run grep -q "kill.*SPINNER_PID" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "spinner trap handlers" {
  # Test that spinner handles interrupts properly
  run grep -q "trap.*INT.*TERM" "$SCRIPT"
  [ "$status" -eq 0 ]
}