# Feature Specification: GraphQL Batch Query for Check Statuses

**Feature Branch**: `001-graphql-batch-query` (merged)
**Created**: 2026-01-06
**Completed**: 2026-01-06
**Status**: ✅ Complete (v0.7.0)
**Input**: User description: "Refactor the tool to use GitHub GraphQL batch query to reduce API calls: use a single GraphQL batch query to fetch all check suite statuses."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Fast Status Display with Reduced API Calls (Priority: P1)

As a developer using `gh log-ci` to check CI status for multiple commits, I want the tool to fetch all check statuses in a single API call so that results appear faster and I consume less API rate limit.

**Why this priority**: This is the core value proposition of the refactor. It directly addresses the primary performance limitation noted in the README ("One REST API call per commit") and reduces API consumption, which is critical for users with rate limit constraints.

**Independent Test**: Can be fully tested by running `gh log-ci` and verifying that (1) only one GraphQL API call is made regardless of commit count, (2) all commit statuses are displayed correctly, and (3) the output matches current REST API behavior.

**Acceptance Scenarios**:

1. **Given** I run `gh log-ci --limit 15` on a repo with 15 commits, **When** the tool fetches check statuses, **Then** only ONE GraphQL API call is made (versus 15 REST calls currently)
2. **Given** I run `gh log-ci --limit 5`, **When** GraphQL query returns check statuses, **Then** all 5 commits show correct status icons (✅, ❌, 🕓, etc.)
3. **Given** I have limited API rate quota remaining, **When** I run `gh log-ci --limit 50`, **Then** I consume significantly fewer API calls compared to REST approach
4. **Given** I run `gh log-ci --checks` for detailed view, **When** GraphQL returns check run details, **Then** per-check summaries match current REST output format

---

### User Story 2 - Fallback to REST API (Priority: P2)

As a user running `gh log-ci` on a GitHub Enterprise Server that may not support GraphQL Checks API, I want the tool to automatically fall back to REST API so that I can still use the tool regardless of my GitHub version.

**Why this priority**: Ensures backward compatibility and maintains tool functionality across different GitHub environments. Not all GitHub Enterprise versions support the GraphQL Checks API.

**Independent Test**: Can be tested independently by mocking a GraphQL API failure and verifying REST API is used as fallback with correct output.

**Acceptance Scenarios**:

1. **Given** GitHub API returns an error for GraphQL query, **When** the tool detects the error, **Then** it automatically retries using REST API endpoints
4. **Given** I run `gh log-ci --checks` for detailed view, **When** GraphQL returns check run details, **Then** per-check summaries match current REST output format

---

### User Story 2 - REST Mode Option for Compatibility (Priority: P2)

As a user on GitHub Enterprise Server <3.4 or with specific API preferences, I want the option to use REST API mode so that I can still use the tool when GraphQL is unavailable.

**Why this priority**: Some GitHub Enterprise versions don't support GraphQL Checks API. Providing explicit REST mode ensures tool works everywhere.

**Independent Test**: Can be tested by using `--use-rest` flag and verifying REST API is used with parallel processing.

**Acceptance Scenarios**:

1. **Given** I run `gh log-ci --use-rest --concurrency 4`, **When** the tool executes, **Then** it uses REST API with 4 parallel workers
2. **Given** I have `LOG_CI_FORCE_REST=1` environment variable set, **When** I run `gh log-ci`, **Then** GraphQL is bypassed and REST API is used
3. **Given** GraphQL query fails on my GHES instance, **When** I see the error message, **Then** it suggests using --use-rest flag

---

### Edge Cases

- What happens when GraphQL query returns partial results (some commits missing check data)?
- What happens if commit SHAs are invalid or don't exist on remote?
- How does the tool handle very large commit counts (>100) where GraphQL response might be huge?
- What happens when check suites exist but have no check runs?
- How does caching interact with GraphQL responses (cache key strategy)?
- What happens if GraphQL query times out or returns errors?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST use GitHub GraphQL API to fetch check run statuses for all commits in a single batch query
- **FR-002**: System MUST transform GraphQL response data into the same internal format currently used by REST API code
- **FR-003**: System MUST maintain identical output format and icons (✅, ❌, 🕓, 🔁, 🚫, ⚠, ⏲, ➖, ❔) regardless of GraphQL vs REST API
- **FR-004**: System MUST automatically detect GraphQL API failures and fall back to REST API approach
- **FR-005**: System MUST respect existing `--api-timeout` flag for GraphQL queries
- **FR-006**: System MUST preserve all current CLI flags and environment variables without breaking changes
- **FR-007**: System MUST handle GraphQL pagination if commit count exceeds single query limits
- **FR-008**: System MUST maintain success-only caching behavior with GraphQL responses
- **FR-009**: System MUST work with both GitHub.com and GitHub Enterprise Server
- **FR-010**: System MUST provide a way to force REST API mode (flag or environment variable)
- **FR-011**: System MUST aggregate check run statuses identically to current logic (priority: failure > pending > cancelled > success)
- **FR-012**: System MUST handle blocked/queued runs detection (🔁 icon) with GraphQL data

### Key Entities *(include if feature involves data)*

- **GraphQL Query**: Batch query that fetches commits with associated check suites and check runs in a single request
- **Check Run Status**: Maps GraphQL check run conclusion/status fields to internal status representation
- **API Response Transformer**: Converts GraphQL nested structure to flat format compatible with existing status aggregation logic
- **Fallback Strategy**: Decision logic that detects GraphQL failures and switches to REST mode

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: GraphQL mode reduces API calls from N (number of commits) to 1 for standard usage
- **SC-002**: Users experience faster results when checking 10+ commits (measurable via `time gh log-ci --limit 20`)
- **SC-003**: All existing bats tests pass without modification (output behavior unchanged)
- **SC-004**: GraphQL query completes within existing `--api-timeout` limit (default 30s) for up to 50 commits
- **SC-005**: Tool successfully falls back to REST API when GraphQL is unavailable (tested via error injection)
- **SC-006**: Zero breaking changes to CLI interface (all flags and environment variables work identically)
- **SC-007**: Shellcheck passes with no new warnings or errors
- **SC-008**: Performance improvement is measurable: at least 50% reduction in total API call time for 15+ commits
