# Tasks: GraphQL Batch Query for Check Statuses

**Feature Branch**: `001-graphql-batch-query`
**Input**: Design documents from `/specs/001-graphql-batch-query/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/graphql-query.md

**Constitution Reminder**: All changes MUST follow Test-First Development (Principle I). Write tests FIRST, ensure they FAIL, then implement.

## Task Format: `- [ ] [ID] [P?] [Story?] Description with file path`

- **Checkbox**: `- [ ]` (markdown checkbox)
- **[P]**: Task can run in parallel (different files, no blocking dependencies)
- **[Story]**: User story label (US1, US2, US3) - required for user story phases only
- **File paths**: Exact paths to files being modified/created

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Prepare development environment and verify baseline

- [ ] T001 Verify current branch is `001-graphql-batch-query` and all planning docs committed
- [ ] T002 Run baseline tests to ensure starting point is clean: `make test` (shellcheck + bats)
- [ ] T003 Document current line count of gh-log-ci: `wc -l gh-log-ci` (baseline: ~417 lines)
- [ ] T004 Create new test file tests/graphql_batch.bats with test skeleton

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core GraphQL infrastructure that must be complete before user story implementation

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T005 Add `USE_REST` variable to environment defaults (line ~63 in gh-log-ci)
- [ ] T006 Add `--use-rest` flag to argument parsing (lines ~70-119 in gh-log-ci)
- [ ] T007 Update `show_help()` function with `--use-rest` flag documentation (lines ~8-50 in gh-log-ci)
- [ ] T008 Add `LOG_CI_FORCE_REST` environment variable support (line ~63 in gh-log-ci)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Fast Status Display with Reduced API Calls (Priority: P1) 🎯 MVP

**Goal**: Replace N REST API calls with single GraphQL batch query to fetch all commit check statuses

**Independent Test**: Run `gh log-ci --limit 15` and verify (1) only one GraphQL API call made, (2) all commit statuses displayed correctly, (3) output matches REST API behavior

### Tests for User Story 1 (REQUIRED per Constitution) ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T009 [P] [US1] Write Bats test in tests/graphql_batch.bats: verify GraphQL query construction with limit 5
- [ ] T010 [P] [US1] Write Bats test in tests/graphql_batch.bats: verify single GraphQL call made vs multiple REST calls
- [ ] T011 [P] [US1] Write Bats test in tests/graphql_batch.bats: verify GraphQL output matches REST output (parity test)
- [ ] T012 [P] [US1] Write Bats test in tests/graphql_batch.bats: verify transformation of GraphQL response to TSV format
- [ ] T013 [P] [US1] Run `make test` - new tests should FAIL (functions not yet implemented)

### Implementation for User Story 1

- [ ] T014 [US1] Implement `fetch_checks_graphql()` function in gh-log-ci (insert after line ~220, before main loop)
- [ ] T015 [P] [US1] Implement `transform_graphql_response()` function in gh-log-ci (use jq to flatten nested JSON to TSV)
- [ ] T016 [US1] Implement `group_by_sha()` function in gh-log-ci (group TSV lines by commit SHA for aggregation)
- [ ] T017 [US1] Add GraphQL code path to main loop in gh-log-ci (lines ~274-350): attempt GraphQL before REST
- [ ] T018 [US1] Integrate GraphQL response with existing status aggregation logic (reuse lines ~289-326)
- [ ] T019 [US1] Add timeout handling for GraphQL query using `run_with_timeout()` wrapper (existing function lines ~195-215)
- [ ] T020 [US1] Handle case where GraphQL returns fewer commits than requested (accept partial results)
- [ ] T021 [US1] Handle case where commit has no checkSuites (display ❔ icon)
- [ ] T022 [US1] Verify `--checks` flag works with GraphQL response (per-check run details)
- [ ] T023 [US1] Run `make test` - all tests including new GraphQL tests MUST pass
- [ ] T024 [US1] Manual test: run `gh log-ci --limit 5` and verify single GraphQL call made
- [ ] T025 [US1] Manual test: compare outputs `gh log-ci --limit 10` vs `gh log-ci --use-rest --limit 10` (should be identical)
- [ ] T026 [US1] Update README.md: remove "One REST API call per commit" from Limitations section (line ~146)
- [ ] T027 [US1] Update README.md: add GraphQL batch query to Features section (line ~88)
- [ ] T028 [US1] Update AGENTS.md: document GraphQL architecture and query structure (line ~50)
- [ ] T029 [US1] Update VERSION to 0.7.0 in gh-log-ci script header (line ~6)
- [ ] T030 [US1] Run `make test` final verification - all tests MUST pass including shellcheck

**Checkpoint**: User Story 1 complete - GraphQL batch query working, output identical to REST, all tests pass

---

## Phase 4: User Story 2 - Fallback to REST API (Priority: P2)

**Goal**: Automatically detect GraphQL failures and transparently fall back to REST API for backward compatibility

**Independent Test**: Mock GraphQL error (schema unsupported) and verify REST API is used as fallback with correct output

### Tests for User Story 2 (REQUIRED per Constitution) ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T031 [P] [US2] Write Bats test in tests/graphql_batch.bats: verify fallback on GraphQL error response
- [ ] T032 [P] [US2] Write Bats test in tests/graphql_batch.bats: verify fallback on GraphQL timeout
- [ ] T033 [P] [US2] Write Bats test in tests/graphql_batch.bats: verify fallback on missing GraphQL fields (GHES <3.4 simulation)
- [ ] T034 [P] [US2] Update tests/timeout.bats: add GraphQL timeout handling test
- [ ] T035 [P] [US2] Run `make test` - new fallback tests should FAIL (fallback logic not yet implemented)

### Implementation for User Story 2

- [ ] T036 [US2] Add error detection in `fetch_checks_graphql()`: check for `errors` key in JSON response
- [ ] T037 [US2] Add error detection in `fetch_checks_graphql()`: check for missing data structure (`data.repository.ref.target.history.nodes`)
- [ ] T038 [US2] Add error detection in `fetch_checks_graphql()`: check for non-zero exit code from `gh api graphql`
- [ ] T039 [US2] Implement fallback logic in main loop: if GraphQL fails, set `USE_REST=1` and execute REST code path
- [ ] T040 [US2] Add debug logging for fallback: `[GraphQL fallback to REST]` when `LOG_CI_CACHE_DEBUG=1`
- [ ] T041 [US2] Test fallback with invalid GraphQL field (simulate GHES <3.4): verify REST API used
- [ ] T042 [US2] Test fallback with GraphQL timeout: set `--api-timeout 1` and verify REST fallback
- [ ] T043 [US2] Run `make test` - all tests including fallback tests MUST pass
- [ ] T044 [US2] Update README.md: document GHES compatibility and automatic fallback (add to Features section)
- [ ] T045 [US2] Update AGENTS.md: document fallback strategy and error detection logic

**Checkpoint**: User Story 2 complete - automatic fallback working, GHES compatibility ensured

---

## Phase 5: User Story 3 - Maintain Performance with Parallel Processing (Priority: P3)

**Goal**: Provide `--use-rest` flag for users who prefer REST API mode with existing parallel processing

**Independent Test**: Run `gh log-ci --use-rest --concurrency 4` and verify parallel REST calls work with concurrency control

### Tests for User Story 3 (REQUIRED per Constitution) ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [ ] T046 [P] [US3] Write Bats test in tests/graphql_batch.bats: verify `--use-rest` flag bypasses GraphQL
- [ ] T047 [P] [US3] Write Bats test in tests/graphql_batch.bats: verify `LOG_CI_FORCE_REST=1` bypasses GraphQL
- [ ] T048 [P] [US3] Write Bats test in tests/graphql_batch.bats: verify `--use-rest` works with `--concurrency` flag
- [ ] T049 [P] [US3] Update tests/help.bats: verify `--use-rest` flag appears in help text
- [ ] T050 [P] [US3] Run `make test` - new REST mode tests should FAIL (flag already added in Phase 2, just needs verification logic)

### Implementation for User Story 3

- [ ] T051 [US3] Verify `--use-rest` flag parsing works correctly (already implemented in T006)
- [ ] T052 [US3] Verify `LOG_CI_FORCE_REST` environment variable works (already implemented in T008)
- [ ] T053 [US3] Add conditional in main loop: if `USE_REST == 1`, skip GraphQL attempt entirely
- [ ] T054 [US3] Verify REST code path (existing lines ~274-350) remains unchanged and functional
- [ ] T055 [US3] Test with `--use-rest --concurrency 8`: verify parallel REST calls work
- [ ] T056 [US3] Test with `LOG_CI_FORCE_REST=1`: verify GraphQL bypassed
- [ ] T057 [US3] Run `make test` - all tests including REST mode tests MUST pass
- [ ] T058 [US3] Update README.md: document `--use-rest` flag and `LOG_CI_FORCE_REST` env var in Configuration section
- [ ] T059 [US3] Update AGENTS.md: document when to use REST mode vs GraphQL mode

**Checkpoint**: User Story 3 complete - users have option to force REST mode if needed

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, performance validation, documentation completeness

### Integration & Testing

- [ ] T060 [P] Run full test suite: `make test` (shellcheck + all bats tests)
- [ ] T061 [P] Verify cache behavior with GraphQL: run twice, second run should use cache
- [ ] T062 [P] Update tests/cache_success.bats: verify caching works identically with GraphQL responses
- [ ] T063 [P] Test with `--no-cache` flag: verify GraphQL query executed even for cached commits
- [ ] T064 [P] Test watch mode with GraphQL: `gh log-ci --watch --watch-interval 5`
- [ ] T065 Test edge case: commits with >100 check runs (document limitation if needed)
- [ ] T066 Test edge case: GraphQL returns partial results (some commits missing check data)
- [ ] T067 Test blocked queued detection with GraphQL response (🔁 icon)

### Performance Validation

- [ ] T068 Measure API call reduction: count calls for `--limit 15` (GraphQL: 1, REST: 15)
- [ ] T069 Benchmark execution time: `time gh log-ci --limit 20` (compare GraphQL vs REST)
- [ ] T070 Verify 50%+ performance improvement for 15+ commits (SC-008)
- [ ] T071 Test with large commit count: `gh log-ci --limit 50` (verify <30s timeout)
- [ ] T072 Monitor cache hit rate with `LOG_CI_CACHE_DEBUG=1`

### Documentation & Release

- [ ] T073 Review README.md: ensure all GraphQL features documented
- [ ] T074 Review AGENTS.md: ensure all implementation details captured
- [ ] T075 Update CHANGELOG in README.md: add 0.7.0 entry with GraphQL feature
- [ ] T076 Verify all constitution principles satisfied (final checklist)
- [ ] T077 Run `make test` one final time - must be 100% green
- [ ] T078 Commit changes with conventional commit message: `refactor: add GraphQL batch query for check statuses`
- [ ] T079 Push feature branch to remote: `git push origin 001-graphql-batch-query`
- [ ] T080 Open pull request against master with comprehensive description

---

## Dependencies Between User Stories

```
Phase 1 (Setup) → Phase 2 (Foundation) → Phase 3 (US1) → Phase 4 (US2) → Phase 5 (US3) → Phase 6 (Polish)
                                              ↓              ↓              ↓
                                            MVP          Fallback      Optional
```

**Critical Path**: T001 → T005-T008 → T009-T030 → T031-T045 → T046-T059 → T060-T080

**Parallel Opportunities** (marked with [P]):
- All test writing tasks can be done in parallel (T009-T013, T031-T035, T046-T050)
- Independent function implementations can be parallel (T014-T015 can be done together)
- Documentation updates can be done in parallel (T026-T028, T044-T045, T058-T059)
- Final testing and validation can be parallel (T060-T067, T068-T072)

---

## Implementation Strategy

### MVP First (Minimum Viable Product)
**Focus**: User Story 1 (P1) = Phases 1-3 (T001-T030)

This delivers the core value: GraphQL batch query reducing API calls from N to 1.

**Estimated Time**: 2-3 days

**Deliverables**:
- GraphQL query working
- Output identical to REST
- All tests passing
- Documentation updated
- Version bumped to 0.7.0

### Incremental Delivery

**Iteration 1** (MVP): US1 - Fast Status Display (T001-T030)
- ✅ GraphQL batch query implemented
- ✅ Performance improvement measurable
- ✅ Output parity with REST

**Iteration 2**: US2 - Fallback to REST (T031-T045)
- ✅ Backward compatibility ensured
- ✅ GHES <3.4 support via fallback
- ✅ Error handling robust

**Iteration 3**: US3 - REST Mode Option (T046-T059)
- ✅ User control over API mode
- ✅ Flexibility maintained
- ✅ Power users satisfied

**Iteration 4**: Polish & Release (T060-T080)
- ✅ Performance validated
- ✅ Documentation complete
- ✅ PR ready for review

---

## Task Execution Checklist

Before marking a task complete:

1. ✅ Code changes committed with conventional commit message
2. ✅ `make test` passes (shellcheck + bats)
3. ✅ Manual testing performed (if applicable)
4. ✅ Documentation updated (if behavior changes)
5. ✅ No shellcheck warnings introduced
6. ✅ Constitution principles upheld (test-first, single-file, etc.)

---

## Success Metrics (from spec.md)

Track these throughout implementation:

- **SC-001**: ✅ API calls reduced from N to 1 (verify in T068)
- **SC-002**: ✅ Faster results for 10+ commits (verify in T069)
- **SC-003**: ✅ All existing bats tests pass (verify in T023, T043, T057, T077)
- **SC-004**: ✅ GraphQL completes within 30s timeout (verify in T071)
- **SC-005**: ✅ Fallback works when GraphQL unavailable (verify in T041-T042)
- **SC-006**: ✅ Zero breaking changes to CLI (verify in T025, T055-T056)
- **SC-007**: ✅ Shellcheck passes with no new warnings (verify in T030, T077)
- **SC-008**: ✅ 50%+ reduction in API call time (verify in T070)

---

**Total Tasks**: 80
**Estimated Effort**: 3-5 days for experienced Bash developer
**Constitution Compliance**: ✅ All principles satisfied
**Next Step**: Begin Phase 1 (Setup) - T001
