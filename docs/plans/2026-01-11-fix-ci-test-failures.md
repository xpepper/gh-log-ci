# Fix CI Test Failures - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix two failing tests in GitHub CI by (1) handling empty SHA_MAP when git log fails, and (2) making tests resilient to different default branch names (master vs main).

**Architecture:** The script has a `set -u` flag that causes unbound variable errors. When `git log` fails (invalid branch/SHA), the SHA_MAP array is never populated, causing a crash. Tests also hardcode `origin/master` which may not exist in all CI environments.

**Tech Stack:** Bash, Bats testing framework, GitHub Actions

---

### Task 1: Add validation after git log to prevent empty SHA_MAP crash

**Files:**
- Modify: `gh-log-ci:423-424`

**Step 1: Write the failing test**

First, let's add a test that verifies the script exits gracefully with code 1 when given an invalid SHA:

```bash
# This test already exists but expects exit code 1.
# The issue is the script crashes with exit code 127 (unbound variable).
# We'll verify this behavior first.
```

**Step 2: Run test to verify it fails**

Run: `./gh-log-ci "invalidsha123" --use-rest 2>&1; echo "Exit: $?"`

Expected: Script crashes with "unbound variable" error, exit code 127

**Step 3: Implement minimal fix**

Add validation after `git log` at line 423. Check if `TOTAL` is 0 (no commits fetched) and exit gracefully:

```bash
TOTAL=$INDEX

# NEW: Validate that we got commits before proceeding
if [[ "$TOTAL" -eq 0 ]]; then
  echo "Error: No commits found. Invalid branch or commit SHA." >&2
  exit 1
fi

TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t ghlogci)
```

**Step 4: Run test to verify it passes**

Run: `./gh-log-ci "invalidsha123" --use-rest 2>&1; echo "Exit: $?"`

Expected: Clean error message, exit code 1

**Step 5: Commit**

```bash
git add gh-log-ci
git commit -m "fix: validate git log output to prevent unbound variable error"
```

---

### Task 2: Make test flexible for default branch name (master vs main)

**Files:**
- Modify: `tests/commit_sha.bats:55-65`

**Step 1: Analyze current hardcoding**

Current test (line 57):
```bash
SHA=$(git rev-parse origin/master)
```

This assumes `origin/master` exists. In CI environments where default branch is `main`, this may fail.

**Step 2: Implement flexible branch detection**

Replace hardcoded `origin/master` with logic that tries both `origin/master` and `origin/main`:

```bash
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
```

**Step 3: Run test locally to verify it works**

Run: `bats tests/commit_sha.bats --filter "works with GraphQL mode"`

Expected: PASS

**Step 4: Test with both master and main scenarios**

```bash
# Simulate main-only environment
git branch -r | grep -q origin/main && echo "main exists" || echo "main not found"
```

**Step 5: Commit**

```bash
git add tests/commit_sha.bats
git commit -m "test: make commit SHA test flexible for master/main branches"
```

---

### Task 3: Verify all tests pass locally

**Files:**
- Test: All tests in `tests/` directory

**Step 1: Run full test suite**

Run: `make test`

Expected: All tests pass (shellcheck + bats)

**Step 2: Run specific failing tests**

Run: `bats tests/commit_sha.bats -t`

Expected: All 8 tests pass, including test 5 and test 8

**Step 3: Run ci-local script**

Run: `make ci-local`

Expected: Clean pass with no failures

**Step 4: Commit any additional fixes**

If issues found, fix and commit:
```bash
git add .
git commit -m "test: additional fixes for CI test failures"
```

---

### Task 4: Push and verify GitHub CI passes

**Files:**
- Remote: GitHub repository

**Step 1: Push changes to GitHub**

Run: `git push origin HEAD`

**Step 2: Monitor GitHub Actions workflow**

Go to: https://github.com/xpepper/gh-log-ci/actions

Expected: All CI checks pass, including both previously failing tests

**Step 3: If CI fails, debug with additional logging**

Add diagnostic step if needed:
```yaml
- name: Debug git state
  run: |
    echo "=== Remote branches ==="
    git branch -r
    echo "=== origin/master ==="
    git rev-parse origin/master || echo "NOT FOUND"
    echo "=== origin/main ==="
    git rev-parse origin/main || echo "NOT FOUND"
```

**Step 4: Final commit if CI adjustments needed**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add diagnostic logging for git state"
git push
```

---

## Summary

**Root causes fixed:**
1. Empty `SHA_MAP` array when `git log` fails now exits gracefully with code 1
2. Tests now flexible for both `master` and `main` default branches
3. Added validation prevents unbound variable crashes

**Test coverage:**
- Invalid SHA input produces clean error (exit 1)
- GraphQL mode works with both master/main branches
- All existing tests continue to pass
