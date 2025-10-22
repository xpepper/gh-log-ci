#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
}

@test "fails on invalid api-timeout" {
  run "$SCRIPT" --api-timeout foo
  [ "$status" -eq 1 ]
  [[ "$output" == *"--api-timeout must be a positive integer"* ]]
}

@test "accepts api-timeout" {
  run "$SCRIPT" --api-timeout 5 --limit 1 --branch "$(git rev-parse --abbrev-ref HEAD)"
  [ "$status" -eq 0 ]
}
