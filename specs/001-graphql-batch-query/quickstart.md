# Quickstart: GraphQL Batch Query Development

**Feature**: GraphQL batch query implementation for gh-log-ci
**Branch**: `001-graphql-batch-query`
**Date**: 2026-01-06

## Overview

This guide helps developers get started with implementing and testing the GraphQL batch query refactor. The refactor replaces N individual REST API calls with a single GraphQL query, improving performance and reducing rate limit consumption.

## Prerequisites

**Required**:
- Bash 4.0+ (macOS: upgrade via Homebrew if needed)
- `gh` CLI installed and authenticated (`gh auth login`)
- `git` installed
- Access to a GitHub repository with commits and CI workflows

**Testing Tools**:
- [Bats](https://github.com/bats-core/bats-core) - Behavioral test framework
- [Shellcheck](https://www.shellcheck.net/) - Bash static analysis

**Install Testing Tools** (macOS):
```bash
brew install bats-core shellcheck
```

## Quick Setup

### 1. Clone and Switch to Feature Branch

```bash
# If not already on feature branch
git checkout 001-graphql-batch-query

# Verify branch
git branch --show-current
# Should output: 001-graphql-batch-query
```

### 2. Verify Current Functionality

```bash
# Test current REST API implementation
./gh-log-ci --limit 5

# Run existing tests
make test
# Or: shellcheck gh-log-ci && bats tests
```

### 3. Review Planning Documents

```bash
# Read feature specification
cat specs/001-graphql-batch-query/spec.md

# Read implementation plan
cat specs/001-graphql-batch-query/plan.md

# Read research findings
cat specs/001-graphql-batch-query/research.md

# Review data model
cat specs/001-graphql-batch-query/data-model.md

# Review GraphQL contract
cat specs/001-graphql-batch-query/contracts/graphql-query.md
```

## Development Workflow

### Phase 1: Implement GraphQL Query Function

**Location**: Add new function in `gh-log-ci` (around line 220, before main loop)

**Implementation Steps**:

1. **Add `fetch_checks_graphql()` function**:
```bash
fetch_checks_graphql() {
  local owner="$1"
  local repo="$2"
  local branch="$3"
  local limit="$4"

  local query='
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
}
'

  # Execute query with timeout
  run_with_timeout "$API_TIMEOUT" gh api graphql \
    -f query="$query" \
    -f owner="$owner" \
    -f repo="$repo" \
    -f branch="refs/heads/$branch" \
    -F limit="$limit" 2>&1
}
```

2. **Test manually**:
```bash
# Edit gh-log-ci to add the function
# Then test with a small limit
./gh-log-ci --limit 3

# Check for GraphQL errors
LOG_CI_CACHE_DEBUG=1 ./gh-log-ci --limit 3 2>&1 | grep -i graphql
```

### Phase 2: Implement Response Transformation

**Add `transform_graphql_response()` function**:

```bash
transform_graphql_response() {
  local response="$1"

  # Transform nested GraphQL to flat TSV
  jq -r '
    .data.repository.ref.target.history.nodes[] as $commit |
    $commit.oid as $sha |
    (
      $commit.checkSuites.nodes[]? |
      .checkRuns.nodes[]? |
      [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase)]
    ) |
    @tsv
  ' <<< "$response"
}
```

**Test transformation**:
```bash
# Create test GraphQL response
cat > /tmp/test-graphql.json <<'EOF'
{
  "data": {
    "repository": {
      "ref": {
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "abc123",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"}
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          }
        }
      }
    }
  }
}
EOF

# Test transformation (after adding function to gh-log-ci)
source gh-log-ci  # Load functions
transform_graphql_response "$(cat /tmp/test-graphql.json)"
# Expected: abc123	build	completed	success
```

### Phase 3: Integrate with Main Loop

**Modify main loop** (around lines 274-350):

```bash
# Before existing REST API loop, add GraphQL attempt
if [[ "$USE_REST" != "1" ]]; then
  GRAPHQL_RESPONSE=$(fetch_checks_graphql "$OWNER" "$REPO" "$BRANCH" "$LIMIT")

  if [[ $? -eq 0 ]] && ! echo "$GRAPHQL_RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
    # GraphQL success - use transformed response
    GRAPHQL_TSV=$(transform_graphql_response "$GRAPHQL_RESPONSE")

    # Process GraphQL response (group by SHA and aggregate)
    # ... (implementation continues)
  else
    # GraphQL failed - fall back to REST
    [[ "$CACHE_DEBUG" == "1" ]] && echo "[GraphQL fallback to REST]" >&2
    USE_REST=1  # Force REST for this execution
  fi
fi

# Existing REST API loop runs if USE_REST=1 or GraphQL failed
if [[ "$USE_REST" == "1" ]]; then
  # ... existing REST API code ...
fi
```

### Phase 4: Add Feature Flag

**Add to argument parsing** (lines 70-119):

```bash
USE_REST="${LOG_CI_FORCE_REST:-0}"

# In case statement:
--use-rest)
  USE_REST=1
  ;;
```

**Update help text** (lines 7-50):

```bash
--use-rest             Force REST API mode (bypass GraphQL)
```

### Phase 5: Test End-to-End

```bash
# Test GraphQL mode (default)
./gh-log-ci --limit 5

# Test REST mode (force)
./gh-log-ci --use-rest --limit 5

# Compare outputs (should be identical)
diff <(./gh-log-ci --limit 5) <(./gh-log-ci --use-rest --limit 5)

# Test with cache
./gh-log-ci --limit 5  # First run (cache miss)
./gh-log-ci --limit 5  # Second run (cache hit)
```

## Testing Strategy

### Unit Tests (Bats)

**Create `tests/graphql_batch.bats`**:

```bash
#!/usr/bin/env bats

@test "GraphQL query is constructed correctly" {
  # Test query construction with various parameters
  # Mock gh api graphql command
}

@test "GraphQL response is transformed to TSV" {
  # Test transformation with sample GraphQL JSON
}

@test "GraphQL error triggers REST API fallback" {
  # Mock GraphQL error, verify REST API called
}

@test "GraphQL and REST outputs are identical" {
  # Run both modes, compare outputs
}

@test "--use-rest flag bypasses GraphQL" {
  # Verify GraphQL not called when flag set
}
```

**Run new tests**:
```bash
bats tests/graphql_batch.bats
```

### Update Existing Tests

**`tests/cache_success.bats`**:
- Verify caching works with GraphQL responses
- Ensure cache key (SHA) works identically

**`tests/timeout.bats`**:
- Test GraphQL timeout handling
- Verify ⏲ icon displayed on timeout

**`tests/help.bats`**:
- Verify `--use-rest` flag appears in help text

### Static Analysis

```bash
# Run shellcheck (should pass with no new warnings)
shellcheck gh-log-ci

# Check for common issues
shellcheck -x gh-log-ci  # Follow sourced files
```

### Integration Testing

```bash
# Test on real repository
gh log-ci --limit 10

# Test with various flags
gh log-ci --limit 20 --checks
gh log-ci --watch --watch-interval 5
gh log-ci --no-cache --limit 15

# Test fallback (simulate GHES <3.4)
# Manually modify query to use unsupported field, verify fallback
```

## Performance Measurement

### Measure API Call Reduction

**Before (REST API)**:
```bash
# Count API calls (REST mode)
time ./gh-log-ci --use-rest --limit 15 2>&1 | grep -c "gh api /repos"
# Expected: 15 calls
```

**After (GraphQL)**:
```bash
# Count API calls (GraphQL mode)
time ./gh-log-ci --limit 15 2>&1 | grep -c "gh api graphql"
# Expected: 1 call
```

### Measure Execution Time

```bash
# Benchmark REST mode
time for i in {1..5}; do
  ./gh-log-ci --use-rest --limit 15 --no-cache >/dev/null
done

# Benchmark GraphQL mode
time for i in {1..5}; do
  ./gh-log-ci --limit 15 --no-cache >/dev/null
done

# Calculate average improvement
```

### Monitor Cache Hit Rate

```bash
# Enable cache debugging
export LOG_CI_CACHE_DEBUG=1

# First run (cache miss)
./gh-log-ci --limit 15 2>&1 | tee /tmp/run1.log

# Second run (cache hit)
./gh-log-ci --limit 15 2>&1 | tee /tmp/run2.log

# Count cache hits
grep -c "cache hit" /tmp/run2.log
```

## Debugging

### Enable Debug Mode

```bash
# Enable cache debugging
export LOG_CI_CACHE_DEBUG=1

# Run with debug output
./gh-log-ci --limit 5
```

### Inspect GraphQL Response

```bash
# Capture raw GraphQL response
gh api graphql -f query='...' -f owner="xpepper" -f repo="gh-log-ci" -f branch="refs/heads/master" -F limit=5 | jq .
```

### Test Transformation Manually

```bash
# Test jq transformation
echo '{"data":{"repository":{"ref":{"target":{"history":{"nodes":[...]}}}}}}' | jq -r '...'
```

### Verify Fallback Behavior

```bash
# Force GraphQL error (invalid field)
# Edit query to include non-existent field
# Verify REST API fallback activates
```

## Common Issues

### Issue: GraphQL Query Returns Errors

**Symptom**: `errors` key in GraphQL response

**Solution**:
1. Check GitHub API version (GHES <3.4 unsupported)
2. Verify token has `repo` scope
3. Check branch name format (`refs/heads/main` not `main`)

### Issue: Transformation Produces Empty Output

**Symptom**: No TSV lines generated from GraphQL response

**Debugging**:
```bash
# Check if response has expected structure
echo "$GRAPHQL_RESPONSE" | jq '.data.repository.ref.target.history.nodes | length'

# Check if checkSuites are present
echo "$GRAPHQL_RESPONSE" | jq '.data.repository.ref.target.history.nodes[0].checkSuites.nodes | length'
```

### Issue: Shellcheck Warnings

**Common Warnings**:
- SC2086: Quote variables in GraphQL query
- SC2181: Use `if ! command` instead of checking `$?`

**Fix**: Follow shellcheck suggestions

## Next Steps

After completing this quickstart:

1. **Run full test suite**: `make test`
2. **Update documentation**: README.md and AGENTS.md
3. **Commit changes**: Follow conventional commit format (`refactor: add GraphQL batch query`)
4. **Open pull request**: Against `master` branch
5. **Monitor CI**: Ensure all tests pass in GitHub Actions

## References

- [Feature Specification](spec.md)
- [Implementation Plan](plan.md)
- [Research Document](research.md)
- [Data Model](data-model.md)
- [GraphQL Contract](contracts/graphql-query.md)
- [GitHub GraphQL Explorer](https://docs.github.com/en/graphql/overview/explorer)
- [Bats Documentation](https://bats-core.readthedocs.io/)
- [Shellcheck Wiki](https://www.shellcheck.net/wiki/)
