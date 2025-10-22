#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
}

@test "shows help with --help" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--limit"* ]]
}

@test "fails on invalid limit" {
  run "$SCRIPT" --limit abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "accepts limit" {
  run "$SCRIPT" --limit 2 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
}
