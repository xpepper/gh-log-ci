#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
}

@test "fails on invalid watch-interval" {
  run "$SCRIPT" --watch --watch-interval nope --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 1 LOG_CI_WATCH_ONCE=1
  [ "$status" -eq 1 ]
  [[ "$output" == *"--watch-interval must be a positive integer"* ]]
}

@test "single iteration watch mode" {
  LOG_CI_WATCH_ONCE=1 run "$SCRIPT" --watch --watch-interval 2 --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[watch]"* ]]
}
