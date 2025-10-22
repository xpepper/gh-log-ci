#!/usr/bin/env bash
# Local CI convenience script for gh-log-ci
# Runs shellcheck and bats tests; produces a simple summary.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "[CI-LOCAL] shellcheck not found. Install with: brew install shellcheck" >&2
  exit 1
fi

if ! command -v bats >/dev/null 2>&1; then
  echo "[CI-LOCAL] bats not found. Install with: brew install bats-core" >&2
  exit 1
fi

echo "[CI-LOCAL] Shellcheck..."
shellcheck gh-log-ci

echo "[CI-LOCAL] Bats tests..."
set +e
bats tests > ci-bats-output.txt 2>&1
BATS_STATUS=$?
set -e
cat ci-bats-output.txt

if [[ $BATS_STATUS -ne 0 ]]; then
  echo "[CI-LOCAL] ❌ Tests failed" >&2
  exit $BATS_STATUS
fi

echo "[CI-LOCAL] ✅ All checks passed"
