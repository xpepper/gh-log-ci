# Tasks: GraphQL Batch Query for Check Statuses

**Feature Branch**: `004-polish-and-validation` (Phase 5)
**Pull Request**: TBD
**Previous PRs**:
- [#26](https://github.com/xpepper/gh-log-ci/pull/26) - User Story 1 MVP (MERGED)
- [#27](https://github.com/xpepper/gh-log-ci/pull/27) - Remove automatic fallback (MERGED)
- [#28](https://github.com/xpepper/gh-log-ci/pull/28) - User Story 2 REST mode option (MERGED)
**Input**: Design documents from `/specs/001-graphql-batch-query/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/graphql-query.md

**Status**: User Stories 1-2 COMPLETE → Starting Phase 5: Polish & Cross-Cutting (44/65 tasks, 68%)

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

- [X] T014 [US1] Implement `fetch_checks_graphql()` function in gh-log-ci (insert after line ~220, before main loop)
- [X] T015 [P] [US1] Implement `transform_graphql_response()` function in gh-log-ci (use jq to flatten nested JSON to TSV)
- [X] T016 [US1] Implement `group_by_sha()` function in gh-log-ci (group TSV lines by commit SHA for aggregation)
- [X] T017 [US1] Add GraphQL code path to main loop in gh-log-ci (lines ~274-350): attempt GraphQL before REST
- [X] T018 [US1] Integrate GraphQL response with existing status aggregation logic (reuse lines ~289-326)
- [X] T019 [US1] Add timeout handling for GraphQL query using `run_with_timeout()` wrapper (existing function lines ~195-215)
- [X] T020 [US1] Handle case where GraphQL returns fewer commits than requested (accept partial results)
- [X] T021 [US1] Handle case where commit has no checkSuites (display ❔ icon)
- [X] T022 [US1] Verify `--checks` flag works with GraphQL response (per-check run details)
- [X] T023 [US1] Run `make test` - all tests including new GraphQL tests MUST pass
- [X] T024 [US1] Manual test: run `gh log-ci --limit 5` and verify single GraphQL call made
- [X] T025 [US1] Manual test: compare outputs `gh log-ci --limit 10` vs `gh log-ci --use-rest --limit 10` (should be identical)
- [X] T026 [US1] Update README.md: remove "One REST API call per commit" from Limitations section (line ~146)
- [X] T027 [US1] Update README.md: add GraphQL batch query to Features section (line ~88)
- [X] T028 [US1] Update AGENTS.md: document GraphQL architecture and query structure (line ~50)
- [X] T029 [US1] Update VERSION to 0.7.0 in gh-log-ci script header (line ~6)
- [X] T030 [US1] Run `make test` final verification - all tests MUST pass including shellcheck

**Checkpoint**: User Story 1 complete - GraphQL batch query working, output identical to REST, all tests pass

---

## Phase 4: User Story 2 - REST Mode Option for Compatibility (Priority: P2)

**Goal**: Provide `--use-rest` flag for users on GHES <3.4 or with specific API preferences

**Independent Test**: Run `gh log-ci --use-rest --concurrency 4` and verify parallel REST calls work with concurrency control

### Tests for User Story 2 (REQUIRED per Constitution) ⚠️

> **NOTE: Write these tests FIRST, ensure they FAIL before implementation**

- [X] T031 [P] [US2] Write Bats test in tests/graphql_batch.bats: verify `--use-rest` flag bypasses GraphQL
- [X] T032 [P] [US2] Write Bats test in tests/graphql_batch.bats: verify `LOG_CI_FORCE_REST=1` bypasses GraphQL
- [X] T033 [P] [US2] Write Bats test in tests/graphql_batch.bats: verify `--use-rest` works with `--concurrency` flag
- [X] T034 [P] [US2] Update tests/help.bats: verify `--use-rest` flag appears in help text
- [X] T035 [P] [US2] Run `make test` - new REST mode tests should PASS (functionality already implemented)

### Implementation for User Story 2

- [X] T036 [US2] Verify `--use-rest` flag parsing works correctly (already implemented in T006)
- [X] T037 [US2] Verify `LOG_CI_FORCE_REST` environment variable works (already implemented in T008)
- [X] T038 [US2] Verify REST code path remains unchanged and functional
- [X] T039 [US2] Test with `--use-rest --concurrency 8`: verify parallel REST calls work
- [X] T040 [US2] Test with `LOG_CI_FORCE_REST=1`: verify GraphQL bypassed
- [X] T041 [US2] Test GraphQL error handling: verify clear error message suggests --use-rest flag
- [X] T042 [US2] Run `make test` - all tests including REST mode tests MUST pass
- [X] T043 [US2] Update README.md: document `--use-rest` flag and `LOG_CI_FORCE_REST` env var, GHES <3.4 compatibility
- [X] T044 [US2] Update AGENTS.md: document when to use REST mode vs GraphQL mode

**Checkpoint**: User Story 2 complete - users have explicit REST mode option, GHES compatibility documented

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Final integration, performance validation, documentation completeness

### Integration & Testing

- [ ] T045 [P] Run full test suite: `make test` (shellcheck + all bats tests)
- [ ] T046 [P] Verify cache behavior with GraphQL: run twice, second run should use cache
- [ ] T047 [P] Update tests/cache_success.bats: verify caching works identically with GraphQL responses
- [ ] T048 [P] Test with `--no-cache` flag: verify GraphQL query executed even for cached commits
- [ ] T049 [P] Test watch mode with GraphQL: `gh log-ci --watch --watch-interval 5`
- [ ] T050 Test edge case: commits with >100 check runs (document limitation if needed)
- [ ] T051 Test edge case: commits with no check runs (verify ❔ icon displayed)
- [ ] T052 Test edge case: very old commits (verify behavior with archived workflow runs)
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
