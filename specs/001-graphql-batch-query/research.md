# Research: GraphQL Batch Query for Check Statuses

**Date**: 2026-01-06
**Feature**: GraphQL batch query implementation for gh-log-ci

## Executive Summary

This document consolidates research findings for replacing individual REST API calls with a single GraphQL batch query. Key decisions:
- Use GitHub GraphQL API v4 with `gh api graphql`
- Query structure: Repository → Refs → Target → History → CheckSuites → CheckRuns
- Fallback to REST API on GraphQL errors (schema unsupported, timeouts, GHES compatibility)
- Transform GraphQL nested response to flat format compatible with existing aggregation logic
- Cache key remains commit SHA, cache TTL and success-only behavior unchanged

## Decision 1: GraphQL API Access Method

**Decision**: Use `gh api graphql` command with inline query strings

**Rationale**:
- `gh` CLI already provides authenticated GraphQL access
- No additional dependencies required
- Consistent with current REST API approach (`gh api /repos/...`)
- Handles authentication, token refresh, and API version negotiation automatically

**Alternatives Considered**:
- **cURL with manual authentication**: Rejected - requires manual token management, parsing `gh auth token`, less portable
- **External GraphQL client**: Rejected - violates single-script architecture, adds dependencies

**Implementation Pattern**:
```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $branch: String!, $limit: Int!) {
  repository(owner: $owner, name: $repo) {
    ref(qualifiedName: $branch) {
      target {
        ... on Commit {
          history(first: $limit) {
            nodes {
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
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -f branch="refs/heads/$BRANCH" -F limit="$LIMIT"
```

## Decision 2: GraphQL Query Structure

**Decision**: Use Repository → Ref → Target → History → CheckSuites → CheckRuns traversal

**Rationale**:
- `repository.ref.target.history` provides commit list in reverse chronological order (matches current `git log` order)
- `checkSuites` aggregates all check runs for a commit (CI workflows, GitHub Actions, third-party checks)
- `first: N` pagination matches current `--limit` flag behavior
- Nested `checkRuns` provides same data as REST `/commits/{sha}/check-runs` endpoint

**Alternatives Considered**:
- **Search API with commit SHAs**: Rejected - requires separate query per commit (defeats batching purpose), search API doesn't provide check runs
- **Timeline API**: Rejected - doesn't include check run details, requires additional queries
- **Commit object with checkSuites**: Preferred approach, provides all data in single query

**Pagination Strategy**:
- `first: 100` for checkSuites (GitHub limit: 100 per page)
- `first: 100` for checkRuns per suite (GitHub limit: 100 per page)
- For repos with >100 check runs per commit: initial implementation limits to first 100, document as known limitation
- Future enhancement: implement cursor-based pagination with `pageInfo.hasNextPage` and `pageInfo.endCursor`

## Decision 3: Fallback Strategy to REST API

**Decision**: Detect GraphQL errors and transparently fall back to existing REST API implementation

**Rationale**:
- GitHub Enterprise Server versions <3.4 don't support GraphQL Checks API
- Some users may have token scopes that lack GraphQL access but have REST API access
- Network errors, timeouts, or API changes shouldn't break the tool
- Existing REST code is battle-tested and handles edge cases

**Error Detection Conditions**:
1. GraphQL query returns error message containing "Field 'checkSuites' doesn't exist"
2. GraphQL query times out (respects `--api-timeout` flag)
3. `gh api graphql` command exits with non-zero status
4. Response JSON lacks expected `data.repository.ref.target.history.nodes` structure

**Fallback Implementation**:
```bash
fetch_checks_graphql() {
  # Attempt GraphQL query
  local response
  response=$(run_with_timeout "$API_TIMEOUT" gh api graphql -f query='...' ... 2>&1)

  if [[ $? -ne 0 ]] || echo "$response" | grep -q "doesn't exist\|error"; then
    # Log fallback (if debug mode enabled)
    [[ "$CACHE_DEBUG" == "1" ]] && echo "[GraphQL fallback to REST]" >&2
    return 1  # Signal to use REST API code path
  fi

  echo "$response"
}

# Main logic
if ! GRAPHQL_RESPONSE=$(fetch_checks_graphql) && [[ "$LOG_CI_FORCE_REST" != "1" ]]; then
  # Fall back to existing REST API loop
  for SHA in "${SHA_MAP[@]}"; do
    # ... existing REST API code ...
  done
fi
```

## Decision 4: Response Transformation

**Decision**: Transform GraphQL nested structure to tab-delimited format matching REST API output

**Rationale**:
- Existing status aggregation logic (lines 289-326 in gh-log-ci) expects tab-delimited `NAME\tSTATUS\tCONCLUSION` format
- Reusing aggregation logic avoids code duplication and maintains identical behavior
- Transformation can be done with `jq` (available via `gh` dependency)

**Transformation Logic**:
```bash
# GraphQL response structure:
# data.repository.ref.target.history.nodes[].checkSuites.nodes[].checkRuns.nodes[]
#   .name, .status, .conclusion

# Transform to REST API equivalent format
jq -r '
  .data.repository.ref.target.history.nodes[] as $commit |
  $commit.oid as $sha |
  $commit.checkSuites.nodes[]? |
  .checkRuns.nodes[]? |
  [$sha, .name, (.status // ""), (.conclusion // "")] |
  @tsv
' <<< "$GRAPHQL_RESPONSE"
```

**Output Format**:
```
SHA<TAB>CheckRunName<TAB>Status<TAB>Conclusion
SHA<TAB>CheckRunName<TAB>Status<TAB>Conclusion
...
```

This matches existing aggregation loop expectations while preserving commit SHA for grouping.

## Decision 5: Caching Strategy

**Decision**: Maintain identical success-only caching behavior with GraphQL responses

**Rationale**:
- Cache key remains commit SHA (unchanged)
- Cache validation: `OVERALL_ICON=="✅"` AND `pending_count==0` AND no timeout (unchanged)
- TTL remains configurable via `LOG_CI_CACHE_TTL` (unchanged)
- Cache file format: `SHA<TAB>EPOCH_TIMESTAMP` (unchanged)

**Implementation Notes**:
- GraphQL response includes all commits in single call, but cache check happens per-commit
- Cache hit behavior unchanged: skip API call entirely if commit cached
- Cache miss with GraphQL: single query fetches all commits (not just misses)
- Optimization opportunity: build commit SHA list excluding cache hits, pass to GraphQL query (future enhancement)

## Decision 6: Feature Flag for REST Mode

**Decision**: Add `--use-rest` flag and `LOG_CI_FORCE_REST` environment variable

**Rationale**:
- Some users may prefer REST API for specific rate limit budgeting
- Debugging: allows comparing GraphQL vs REST output for parity testing
- Gradual rollout: users can opt-out if GraphQL has issues

**Implementation**:
```bash
# Add to argument parsing
USE_REST="${LOG_CI_FORCE_REST:-0}"
case "$1" in
  --use-rest)
    USE_REST=1
    ;;
esac

# Main logic
if [[ "$USE_REST" == "1" ]]; then
  # Use existing REST API code path
else
  # Try GraphQL, fall back to REST on error
fi
```

## Best Practices: Error Handling

**Timeout Handling**:
- GraphQL query respects `--api-timeout` flag via `run_with_timeout` wrapper (existing function)
- On timeout, display ⏲ icon for all commits (matches current REST behavior)
- Log timeout event if `LOG_CI_CACHE_DEBUG=1`

**Partial Response Handling**:
- If GraphQL returns fewer commits than requested: accept partial results, don't fail
- If commit missing `checkSuites`: treat as zero check runs (show ❔ icon)
- If `checkSuites` present but empty `checkRuns`: treat as no checks (show ❔ icon)

**GraphQL-Specific Errors**:
- `RATE_LIMITED`: Respect `X-RateLimit-Remaining` header, display user-friendly message (future enhancement)
- `FORBIDDEN`: Fall back to REST API (may have different permission model)
- `NOT_FOUND`: Repository or branch doesn't exist, display error and exit (matches current behavior)

## Integration Points

**Existing Code Reuse**:
- `run_with_timeout()`: Wrap GraphQL query (lines 195-215 in gh-log-ci)
- Status aggregation logic: Reuse lines 289-326 for both REST and GraphQL
- Icon mapping: Unchanged (✅, ❌, 🕓, 🔁, 🚫, ⚠, ⏲, ➖, ❔)
- Cache read/write: Reuse lines 234-248 (read), 336-342 (write)
- Progress spinner: Works identically with GraphQL (single query still counts as N "API operations" for UX)

**Modified Sections**:
- Main loop (lines 274-350): Add GraphQL code path before existing REST loop
- Help text: Add `--use-rest` flag documentation (lines 7-50)
- Version bump: Update to 0.7.0 (line 6)

**New Functions**:
```bash
fetch_checks_graphql()    # Execute GraphQL query with error handling
transform_graphql_response()  # Convert nested JSON to flat TSV
detect_blocked_queued_graphql()  # Port blocked detection to GraphQL data
```

## Testing Strategy

**Shellcheck**:
- No new violations introduced
- Ensure proper quoting of variables in GraphQL query construction
- Validate JSON parsing with `jq` doesn't introduce command injection risks

**Bats Tests**:
- `tests/graphql_batch.bats` (new):
  - Test GraphQL query construction with various limits (5, 15, 50)
  - Test response transformation (mock GraphQL response → verify TSV output)
  - Test fallback to REST (mock GraphQL error → verify REST API called)
  - Test parity: GraphQL output matches REST output for same commits
  - Test timeout handling (mock slow GraphQL response → verify ⏲ icon)
  - Test `--use-rest` flag (verify GraphQL bypassed)

- Update existing tests:
  - `tests/cache_success.bats`: Verify caching works with GraphQL responses
  - `tests/timeout.bats`: Verify timeout handling with GraphQL
  - `tests/help.bats`: Verify `--use-rest` flag appears in help text

**Manual Testing**:
- Test on repository with >15 commits and varied check statuses
- Compare `time gh log-ci` before/after (verify performance improvement)
- Test on GitHub Enterprise Server (verify fallback works)
- Test with `LOG_CI_FORCE_REST=1` (verify REST mode works)

## Performance Expectations

**API Call Reduction**:
- Before: N REST calls (one per commit, default 15)
- After: 1 GraphQL call (regardless of commit count)
- Reduction: 93% fewer API calls for 15 commits, 98% for 50 commits

**Latency Improvement**:
- REST API (15 commits, concurrency=4): ~3-5 seconds (4 batches × ~1s per batch)
- GraphQL (15 commits): ~1-2 seconds (single query)
- Expected improvement: 50-60% reduction in total time

**Rate Limit Impact**:
- GitHub.com rate limits: 5000 requests/hour (authenticated)
- Before: 15 commits = 15 requests (~200 executions per hour max)
- After: 15 commits = 1 request (~5000 executions per hour max)
- Improvement: 25× more executions possible within rate limit

## Known Limitations

1. **CheckSuite Pagination**: Initial implementation limits to first 100 check suites per commit and first 100 check runs per suite. For repos with >100 check runs, some may be omitted. This matches REST API behavior (which doesn't paginate check runs by default).

2. **GHES Compatibility**: GitHub Enterprise Server <3.4 lacks GraphQL Checks API. Tool will automatically fall back to REST API, but users won't benefit from performance improvements on older GHES versions.

3. **Mixed Cache Hits**: When some commits are cached and others are not, GraphQL query fetches ALL commits (not just misses). Optimization to pass only uncached SHAs to GraphQL is deferred to future enhancement.

4. **GraphQL Schema Changes**: If GitHub deprecates fields (`checkSuites`, `checkRuns`) or changes response structure, fallback to REST API will activate. Monitoring GitHub API changelog is recommended.

## References

- [GitHub GraphQL API Documentation](https://docs.github.com/en/graphql)
- [GitHub Checks API (GraphQL)](https://docs.github.com/en/graphql/reference/objects#checksuite)
- [GitHub CLI GraphQL Documentation](https://cli.github.com/manual/gh_api)
- [GraphQL Pagination Best Practices](https://graphql.org/learn/pagination/)
- Current gh-log-ci REST implementation: lines 274-350 in `gh-log-ci`
