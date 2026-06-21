#!/usr/bin/env bats

# Verifies the bash version guard added for compatibility with
# associative arrays (declare -A), which require Bash 4.0+.
# macOS ships Bash 3.2 by default, so the script must fail early
# with a clear, actionable error instead of the cryptic
# "declare: -A: invalid option" message.

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
}

# Returns 0 if a Bash 3.2 binary is available for the negative test.
_have_bash3() {
  # macOS system bash is 3.2; some CI images only ship newer bash.
  if [[ -x /bin/bash ]] && /bin/bash -c '(( ${BASH_VERSINFO[0]} < 4 ))' 2>/dev/null; then
    return 0
  fi
  return 1
}

@test "fails with clear error when run under bash < 4" {
  if ! _have_bash3; then
    skip "bash < 4 not available on this system"
  fi

  # Run the script explicitly under the old bash to simulate a
  # user whose `env bash` resolves to 3.2.
  run /bin/bash "$SCRIPT" --help

  [ "$status" -ne 0 ]
  # Error message must mention Bash 4 and be actionable.
  [[ "$output" == *"Bash 4"* || "$output" == *"bash 4"* ]]
  [[ "$output" == *"declare -A"* || "$output" == *"associative"* || "$output" == *"brew install bash"* ]]
}

@test "runs without version error under bash 4+" {
  # Use whatever bash the test harness itself runs under; this file
  # is executed by `bats`, which in our Makefile runs under bash 5.
  if (( BASH_VERSINFO[0] < 4 )); then
    skip "test harness not running under bash 4+"
  fi

  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"declare: -A: invalid option"* ]]
}
