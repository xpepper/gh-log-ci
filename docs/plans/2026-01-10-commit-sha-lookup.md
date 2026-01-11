# Commit SHA Lookup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable `gh log-ci <sha>` to display status for a single specific commit without warnings or extra commits.

**Architecture:** Add commit SHA detection logic before branch detection. When a valid commit SHA is provided as the first positional argument, skip branch detection and use `git log <sha> -n 1` to fetch only that commit. Update GraphQL and REST APIs to work with single-commit mode.

**Tech Stack:** Bash, GitHub CLI (gh), git, bats testing framework

---

## Task 1: Add SHA Detection and Validation

**Files:**
- Modify: `gh-log-ci:125-166`
- Test: `tests/commit_sha.bats` (create)

**Step 1: Write the failing test**

Create test file that verifies SHA detection works:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="$(pwd)/gh-log-ci"
}

@test "accepts valid commit SHA" {
  # Get a real commit SHA from current repo
  SHA=$(git rev-parse HEAD~1)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  # Should show exactly 2 lines (status line + blank line)
  [ $(echo "$output" | wc -l) -eq 2 ]
  # Should contain the SHA
  [[ "$output" == *"${SHA:0:7}"* ]]
  # Should NOT contain warning about remote branch
  [[ "$output" != *"Warning: Remote branch"* ]]
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
```

**Step 2: Run test to verify it fails**

Run: `bats tests/commit_sha.bats`
Expected: FAIL - all tests should fail because SHA detection not implemented

**Step 3: Add SHA detection function before branch detection**

In `gh-log-ci`, add after line 147 (after watch interval validation, before branch determination):

```bash
# Detect if USER_BRANCH is actually a commit SHA
is_commit_sha() {
  local ref="$1"
  [[ -z "$ref" ]] && return 1
  # Try to resolve as commit SHA (supports full and short SHAs)
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null 2>&1
}

# Check if USER_BRANCH is a commit SHA
IS_COMMIT_MODE=0
COMMIT_SHA=""
if [[ -n "$USER_BRANCH" ]] && is_commit_sha "$USER_BRANCH"; then
  IS_COMMIT_MODE=1
  # Resolve to full SHA for consistency
  COMMIT_SHA=$(git rev-parse --verify "$USER_BRANCH^{commit}" 2>/dev/null)
  if [[ -z "$COMMIT_SHA" ]]; then
    echo "Error: Unable to resolve commit SHA: $USER_BRANCH" >&2
    exit 1
  fi
  # In commit mode, we don't need a branch
  BRANCH=""
fi
```

**Step 4: Update branch detection to skip when in commit mode**

Modify the branch determination block (lines 149-165) to wrap in a conditional:

```bash
# Determine branch (BRANCH variable) using auto-detect if USER_BRANCH empty
# Skip branch detection if we're in commit SHA mode
if [[ "$IS_COMMIT_MODE" -eq 0 ]]; then
  if [[ -n "$USER_BRANCH" ]]; then
    BRANCH="$USER_BRANCH"
  else
    GH_DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)"
    if [[ -n "${GH_DEFAULT_BRANCH}" ]]; then
      BRANCH="${GH_DEFAULT_BRANCH}"
    else
      if git show-ref --verify --quiet refs/heads/master || git ls-remote --exit-code origin master &>/dev/null; then
        BRANCH="master"
      elif git show-ref --verify --quiet refs/heads/main || git ls-remote --exit-code origin main &>/dev/null; then
        BRANCH="main"
      else
        BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
      fi
    fi
  fi
fi
```

**Step 5: Run tests to verify they pass**

Run: `bats tests/commit_sha.bats`
Expected: First two tests should pass (SHA detection), last two may still fail (need git log changes)

**Step 6: Commit**

```bash
git add gh-log-ci tests/commit_sha.bats
git commit -m "feat: add commit SHA detection and validation"
```

---

## Task 2: Update Remote Fetch Logic for Commit Mode

**Files:**
- Modify: `gh-log-ci:187-192`

**Step 1: Write the failing test**

Add to `tests/commit_sha.bats`:

```bash
@test "does not emit remote branch warning for commit SHA" {
  SHA=$(git rev-parse HEAD~1)
  run "$SCRIPT" "$SHA" --use-rest
  [ "$status" -eq 0 ]
  # Critical: no warning should appear
  [[ "$output" != *"Warning: Remote branch"* ]]
  [[ "$output" != *"not found on origin"* ]]
}
```

**Step 2: Run test to verify it fails**

Run: `bats tests/commit_sha.bats -f "does not emit remote branch warning"`
Expected: FAIL - warning still appears

**Step 3: Skip remote fetch when in commit mode**

Modify lines 187-192 to wrap the fetch logic:

```bash
# Ensure we have remote branch; fetch quietly, tolerate missing remote branch gracefully.
# Skip this entirely in commit SHA mode since we don't need a remote branch
if [[ "$IS_COMMIT_MODE" -eq 0 ]]; then
  if git ls-remote --exit-code origin "$BRANCH" &>/dev/null; then
    git fetch origin "$BRANCH" --quiet
  else
    echo "Warning: Remote branch '$BRANCH' not found on origin. Using local branch if available." >&2
  fi
fi
```

**Step 4: Run test to verify it passes**

Run: `bats tests/commit_sha.bats -f "does not emit remote branch warning"`
Expected: PASS

**Step 5: Commit**

```bash
git add gh-log-ci tests/commit_sha.bats
git commit -m "fix: skip remote fetch and warning in commit SHA mode"
```

---

## Task 3: Update Git Log Command for Single Commit Mode

**Files:**
- Modify: `gh-log-ci:292-307`

**Step 1: Write the failing test**

Already exists in Task 1, Step 1: "shows single commit without extra commits"

**Step 2: Run test to verify it fails**

Run: `bats tests/commit_sha.bats -f "shows single commit"`
Expected: FAIL - shows multiple commits instead of one

**Step 3: Update run_once() to use commit SHA when available**

Modify the git log command section (lines 297-307) in `run_once()`:

```bash
run_once() {
  INDEX=0
  declare -A LINE_MAP
  declare -A SHA_MAP
  declare -A SUCCESS_CACHE

  # Build git log command based on mode
  if [[ "$IS_COMMIT_MODE" -eq 1 ]]; then
    # Commit mode: show only the specified commit
    LOG_TARGET="$COMMIT_SHA"
    EFFECTIVE_LIMIT=1
  else
    # Branch mode: determine ref to log
    LOG_REF="origin/$BRANCH"
    if ! git show-ref --verify --quiet "refs/remotes/$LOG_REF"; then
      # fallback to local branch name
      LOG_REF="$BRANCH"
    fi
    LOG_TARGET="$LOG_REF"
    EFFECTIVE_LIMIT="$LIMIT"
  fi

  while IFS=$'\t' read -r SHA MESSAGE; do
    LINE_MAP[$INDEX]="$MESSAGE"
    SHA_MAP[$INDEX]="$SHA"
    INDEX=$((INDEX+1))
  done < <(git log "$LOG_TARGET" --color=always --pretty="$FORMAT" -n "$EFFECTIVE_LIMIT")
```

**Step 4: Run test to verify it passes**

Run: `bats tests/commit_sha.bats -f "shows single commit"`
Expected: PASS

**Step 5: Commit**

```bash
git add gh-log-ci
git commit -m "feat: use single commit mode in git log command"
```

---

## Task 4: Update GraphQL Query for Single Commit Mode

**Files:**
- Modify: `gh-log-ci:221-264`

**Step 1: Write the failing test**

Add to `tests/commit_sha.bats`:

```bash
@test "works with GraphQL mode (without --use-rest)" {
  SHA=$(git rev-parse HEAD~1)
  run "$SCRIPT" "$SHA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${SHA:0:7}"* ]]
  [[ "$output" != *"Warning:"* ]]
  # Should show exactly 1 status line
  STATUS_LINES=$(echo "$output" | grep -E '^[✅❌🕓🚫❔⏲🔁]' | wc -l)
  [ "$STATUS_LINES" -eq 1 ]
}
```

**Step 2: Run test to verify it fails**

Run: `bats tests/commit_sha.bats -f "works with GraphQL"`
Expected: FAIL - GraphQL query expects branch ref

**Step 3: Add commit-mode GraphQL query function**

Add new function after `fetch_checks_graphql()`:

```bash
# Fetch check runs for a single commit via GraphQL
fetch_checks_graphql_commit() {
  local owner="$1"
  local repo="$2"
  local sha="$3"

  # shellcheck disable=SC2016  # GraphQL query uses literal $variables
  local query='
query($owner: String!, $repo: String!, $sha: String!) {
  repository(owner: $owner, name: $repo) {
    object(expression: $sha) {
      ... on Commit {
        oid
        checkSuites(first: 100) {
          nodes {
            checkRuns(first: 100) {
              nodes {
                name
                status
                conclusion
              }
            }
          }
        }
      }
    }
  }
}
'

  # Execute query with timeout
  run_with_timeout "$API_TIMEOUT" gh api graphql \
    -f query="$query" \
    -f owner="$owner" \
    -f repo="$repo" \
    -f sha="$sha" 2>&1
}

# Transform single-commit GraphQL response to flat TSV format
transform_graphql_response_commit() {
  local response="$1"

  jq -r '
    .data.repository.object as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase)]
    ) |
    @tsv
  ' <<< "$response" 2>/dev/null || true
}
```

**Step 4: Update GraphQL invocation to use commit query when in commit mode**

Modify the GraphQL section (around line 350-356):

```bash
# GraphQL batch query or REST API mode
if [[ "$USE_REST" != "1" ]]; then
  # Attempt GraphQL batch query
  if [[ "$CACHE_DEBUG" == "1" ]]; then
    if [[ "$IS_COMMIT_MODE" -eq 1 ]]; then
      echo "[GraphQL] Fetching single commit $COMMIT_SHA" >&2
    else
      echo "[GraphQL] Attempting batch query for $TOTAL commits" >&2
    fi
  fi

  if [[ "$IS_COMMIT_MODE" -eq 1 ]]; then
    GRAPHQL_RESPONSE=$(fetch_checks_graphql_commit "$OWNER" "$REPO" "$COMMIT_SHA" 2>&1)
  else
    GRAPHQL_RESPONSE=$(fetch_checks_graphql "$OWNER" "$REPO" "$BRANCH" "$LIMIT" 2>&1)
  fi
  GRAPHQL_EXIT=$?
```

**Step 5: Update GraphQL response transformation**

Modify transformation section (around line 397-398):

```bash
# GraphQL succeeded, transform response
if [[ "$IS_COMMIT_MODE" -eq 1 ]]; then
  GRAPHQL_TSV=$(transform_graphql_response_commit "$GRAPHQL_RESPONSE")
else
  GRAPHQL_TSV=$(transform_graphql_response "$GRAPHQL_RESPONSE")
fi
```

**Step 6: Update GraphQL error checking for commit mode**

Modify error checking (around line 386):

```bash
if [[ "$IS_COMMIT_MODE" -eq 1 ]]; then
  if ! echo "$GRAPHQL_RESPONSE" | jq -e '.data.repository.object' >/dev/null 2>&1; then
    if [[ -n "${SPINNER_PID:-}" && "$NO_SPINNER" -ne 1 ]]; then
      kill "$SPINNER_PID" 2>/dev/null || true
      wait "$SPINNER_PID" 2>/dev/null || true
      printf "\r%-60s\r" ""
    fi
    echo "Error: GraphQL response missing expected data structure for commit." >&2
    echo "Try running with --use-rest flag to use REST API instead." >&2
    exit 1
  fi
else
  if ! echo "$GRAPHQL_RESPONSE" | jq -e '.data.repository.ref.target.history.nodes' >/dev/null 2>&1; then
    if [[ -n "${SPINNER_PID:-}" && "$NO_SPINNER" -ne 1 ]]; then
      kill "$SPINNER_PID" 2>/dev/null || true
      wait "$SPINNER_PID" 2>/dev/null || true
      printf "\r%-60s\r" ""
    fi
    echo "Error: GraphQL response missing expected data structure." >&2
    echo "Try running with --use-rest flag to use REST API instead." >&2
    exit 1
  fi
fi
```

**Step 7: Run test to verify it passes**

Run: `bats tests/commit_sha.bats -f "works with GraphQL"`
Expected: PASS

**Step 8: Commit**

```bash
git add gh-log-ci tests/commit_sha.bats
git commit -m "feat: add GraphQL support for single commit mode"
```

---

## Task 5: Update Help Documentation

**Files:**
- Modify: `gh-log-ci:8-51`

**Step 1: Write the failing test**

Add to `tests/commit_sha.bats`:

```bash
@test "help shows commit SHA usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"<branch>"* ]]
  # Help should document that <branch> can also be a commit SHA
  [[ "$output" == *"commit"* ]] || [[ "$output" == *"SHA"* ]]
}
```

**Step 2: Run test to verify it fails**

Run: `bats tests/commit_sha.bats -f "help shows commit SHA"`
Expected: FAIL or PASS (if "commit" appears elsewhere) - but help should be clearer

**Step 3: Update help text to document commit SHA usage**

Modify `show_help()` function:

```bash
show_help() {
  cat <<'EOF'
gh log-ci - show CI status next to recent commits

Usage:
  gh log-ci [options] [<branch>|<commit-sha>]

 Options:
   --branch <name>        Branch to inspect (alternative to positional <branch>)
   --limit, -n <n>        Number of commits to display (default: 15; env LOG_CI_LIMIT overrides)
   --concurrency, -c <n>  Max parallel API calls (default: 4; env LOG_CI_CONCURRENCY overrides)
   --checks, -C           Show per-check run summaries beneath each commit (env LOG_CI_SHOW_CHECKS=1)
   --no-spinner           Disable loading spinner (env LOG_CI_NO_SPINNER=1)
   --api-timeout <secs>   Max seconds per API request (default: 30; env LOG_CI_API_TIMEOUT)
   --watch                Continuously poll and update commit statuses
   --watch-interval <s>   Seconds between polls in watch mode (default: 10; env LOG_CI_WATCH_INTERVAL)
   --no-cache             Ignore success cache, force fresh API calls for all commits
   --use-rest             Force REST API mode, bypass GraphQL (env LOG_CI_FORCE_REST=1)

Branch auto-detect order when <branch> not supplied:
  1. GitHub default branch (via gh repo view)
  2. master (if exists)
  3. main (if exists)
  4. current HEAD branch

Commit SHA mode:
  When a valid commit SHA (full or short) is provided as the first argument,
  gh log-ci displays status for that single commit only.

Examples:
  gh log-ci                                  # auto-detect branch
  gh log-ci main                             # explicit positional branch
  gh log-ci 7b60fc9                          # show status for single commit
  gh log-ci abc123def                        # works with full SHAs too
  gh log-ci --branch develop --limit 30
  gh log-ci -c 8 -n 50                       # increase parallelism and number of commits
  LOG_CI_SHOW_CHECKS=1 gh log-ci -n 10       # show per-check summaries (env)
  gh log-ci -C --limit 5                     # show per-check summaries (flag)
  gh log-ci --watch                          # watch mode (poll every 10s)
  gh log-ci --watch --watch-interval 30      # watch mode with custom interval

Additional environment:
  LOG_CI_WATCH_INTERVAL   Override default poll interval (10)
  LOG_CI_WATCH_ONCE=1     Internal/testing: run only one watch iteration then exit

Exit codes:
  0 success
  1 setup or API error

EOF
}
```

**Step 4: Run test to verify it passes**

Run: `bats tests/commit_sha.bats -f "help shows commit SHA"`
Expected: PASS

**Step 5: Commit**

```bash
git add gh-log-ci tests/commit_sha.bats
git commit -m "docs: update help text to document commit SHA mode"
```

---

## Task 6: Run Full Test Suite and Verify All Tests Pass

**Files:**
- All test files

**Step 1: Run complete test suite**

Run: `make test`
Expected: All tests pass (including new commit_sha.bats tests)

**Step 2: If any tests fail, fix them**

Review failures and fix issues. Common issues:
- Off-by-one errors in line counting
- Timing issues with API calls
- Cache interactions

**Step 3: Re-run tests until all pass**

Run: `make test`
Expected: 100% pass rate

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test failures"
```

---

## Task 7: Manual Testing and Edge Cases

**Files:**
- None (manual testing)

**Step 1: Test with various commit SHA formats**

```bash
# Test full SHA
FULL_SHA=$(git rev-parse HEAD~3)
./gh-log-ci "$FULL_SHA"

# Test 7-char short SHA
SHORT_SHA=$(git rev-parse --short=7 HEAD~3)
./gh-log-ci "$SHORT_SHA"

# Test 8-char short SHA
MED_SHA=$(git rev-parse --short=8 HEAD~3)
./gh-log-ci "$MED_SHA"
```

Expected: All show single commit status without warnings

**Step 2: Test invalid SHA error handling**

```bash
./gh-log-ci "notavalidsha"
./gh-log-ci "000000000000000000000000000000"
```

Expected: Clear error message, exit code 1

**Step 3: Test that branch mode still works**

```bash
# Auto-detect branch
./gh-log-ci --limit 3

# Explicit branch
./gh-log-ci main --limit 3

# Branch that might look like SHA but isn't
git checkout -b abc123f
./gh-log-ci abc123f
git checkout -
```

Expected: Branch mode works correctly, no regression

**Step 4: Test GraphQL vs REST mode**

```bash
# GraphQL mode (default)
./gh-log-ci 7b60fc9

# REST mode (explicit)
./gh-log-ci 7b60fc9 --use-rest
```

Expected: Both modes produce identical output

**Step 5: Test with --checks flag**

```bash
./gh-log-ci 7b60fc9 --checks
```

Expected: Shows check run details for the single commit

**Step 6: Document any issues found**

If issues are found, create new tasks or fix immediately.

**Step 7: Final verification**

Run the exact command from the feature request:

```bash
./gh-log-ci 7b60fc9
```

Expected output:
```
✅  7b60fc9 - feat: complete GraphQL batch query feature (v0.7.0) - Phase 5 (#29) (Tue Jan 6 01:39:24 2026 +0100) <Pietro Di Bello>

```

(No warning messages, just the status line and blank line)

---

## Task 8: Update Documentation Files

**Files:**
- Modify: `CLAUDE.md`
- Modify: `AGENTS.md`
- Modify: `README.md` (if exists)

**Step 1: Write test for documentation completeness**

Not automated - manual review required.

**Step 2: Update CLAUDE.md with commit SHA mode notes**

Add to the Common Development Commands section:

```markdown
# Testing commit SHA mode
./gh-log-ci 7b60fc9           # Show status for specific commit
./gh-log-ci $(git rev-parse HEAD~5)  # Use full SHA
```

Add to the Architecture Overview section:

```markdown
**Commit SHA Detection (lines 148-165):**
- Detects if positional argument is a valid commit SHA (full or short)
- Uses `git rev-parse --verify` to validate and resolve SHAs
- Skips branch detection and remote fetch when in commit mode
- Sets `IS_COMMIT_MODE=1` and `COMMIT_SHA=<resolved-full-sha>`

**Single Commit Mode:**
- GraphQL query uses `repository.object(expression: $sha)` instead of `ref.target.history`
- Git log uses `git log $COMMIT_SHA -n 1` instead of branch-based log
- No remote branch warnings or unnecessary output
```

**Step 3: Update AGENTS.md with feature description**

Add to the Project Overview section:

```markdown
- **Commit SHA mode**: Display CI status for a single specific commit by providing SHA as argument
```

Add to the Key Components section:

```markdown
### Commit SHA Mode
- **SHA detection**: Lines 148-165 detect and validate commit SHAs
- **Single commit GraphQL**: `fetch_checks_graphql_commit()` and `transform_graphql_response_commit()` functions
- **Conditional logic**: `IS_COMMIT_MODE` flag controls branch vs commit mode throughout script
```

**Step 4: Commit documentation updates**

```bash
git add CLAUDE.md AGENTS.md
git commit -m "docs: document commit SHA mode feature"
```

---

## Task 9: Final Integration Test and Commit

**Files:**
- All modified files

**Step 1: Run complete test suite one final time**

Run: `make test`
Expected: All tests pass

**Step 2: Run shellcheck**

Run: `make shellcheck`
Expected: No warnings or errors

**Step 3: Test both GraphQL and REST modes end-to-end**

```bash
# Test a few different commits
for sha in $(git rev-parse HEAD HEAD~1 HEAD~5); do
  echo "Testing SHA: ${sha:0:7}"
  ./gh-log-ci "$sha" || exit 1
  ./gh-log-ci "$sha" --use-rest || exit 1
done
```

Expected: All commands succeed with correct output

**Step 4: Verify no regressions in branch mode**

```bash
./gh-log-ci --limit 5
./gh-log-ci main --limit 5
./gh-log-ci --use-rest --limit 5
```

Expected: Branch mode works exactly as before

**Step 5: Review all changes**

```bash
git diff master
```

Verify:
- No unintended changes
- Code follows project conventions
- All comments are clear and accurate

**Step 6: Create final commit if needed**

If there are any loose ends:

```bash
git add -A
git commit -m "chore: final cleanup for commit SHA mode feature"
```

**Step 7: Update version number**

Modify version in `gh-log-ci` line 6:

```bash
VERSION="0.8.0"
```

Commit:

```bash
git add gh-log-ci
git commit -m "chore: bump version to 0.8.0"
```

---

## Task 10: Create Pull Request

**Files:**
- None (Git operations)

**Step 1: Push branch to remote**

```bash
git push origin HEAD
```

**Step 2: Create pull request**

```bash
gh pr create --title "feat: add commit SHA lookup mode" --body "$(cat <<'EOF'
## Summary
- Add ability to query CI status for a single commit via `gh log-ci <sha>`
- Works with both full and short commit SHAs
- Supports both GraphQL and REST API modes
- No warnings or extra commits displayed

## Changes
- Add commit SHA detection and validation
- Skip branch detection and remote fetch in commit mode
- Update git log command to show single commit
- Add GraphQL query for single commit mode
- Update documentation and help text
- Add comprehensive test coverage

## Test Plan
- ✅ All existing tests pass
- ✅ New test file `tests/commit_sha.bats` covers commit mode
- ✅ Manual testing with various SHA formats
- ✅ No regressions in branch mode

## Examples

Before:
```
$ gh log-ci 7b60fc9 --use-rest
Warning: Remote branch '7b60fc9' not found on origin. Using local branch if available.
✅  7b60fc9 - feat: complete GraphQL batch query feature (v0.7.0) - Phase 5 (#29)
✅  c6309d9 - feat: add REST mode option for GHES <3.4 compatibility (US2) (#28)
...
```

After:
```
$ gh log-ci 7b60fc9
✅  7b60fc9 - feat: complete GraphQL batch query feature (v0.7.0) - Phase 5 (#29)

```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Verify PR was created successfully**

```bash
gh pr view
```

Expected: PR details displayed correctly

---

## Execution Notes

**Estimated Complexity:** Medium
- Moderate number of changes across the script
- Both GraphQL and REST modes need updates
- Good test coverage required
- Documentation updates essential

**Key Risks:**
- Breaking branch mode (regression testing critical)
- GraphQL query differences between branch and commit modes
- Edge cases with various SHA formats

**Testing Strategy:**
- TDD approach: write tests first, then implement
- Test both GraphQL and REST modes equally
- Verify no regressions in existing functionality
- Manual testing for edge cases

**Success Criteria:**
- `gh log-ci <sha>` shows single commit without warnings
- All existing tests still pass
- New tests cover commit SHA mode comprehensively
- Documentation updated
- Works with both GraphQL and REST modes
