# GraphQL Batch Query Contract for Check Statuses

**Purpose**: Single GraphQL query to fetch all commit check run statuses in one API call

**GitHub API Version**: GraphQL v4
**Minimum GHES Version**: 3.4+ (for `checkSuites` support on Commit type)

## Query Schema

```graphql
query FetchCommitCheckStatuses(
  $owner: String!
  $repo: String!
  $branch: String!
  $limit: Int!
) {
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
```

## Variables

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `owner` | String! | Repository owner (user or org) | `"xpepper"` |
| `repo` | String! | Repository name | `"gh-log-ci"` |
| `branch` | String! | Fully qualified ref name | `"refs/heads/master"` |
| `limit` | Int! | Number of commits to fetch | `15` |

**Note**: `branch` must be fully qualified (`refs/heads/main`), not short name (`main`)

## Response Schema

### Success Response

```json
{
  "data": {
    "repository": {
      "ref": {
        "target": {
          "history": {
            "nodes": [
              {
                "oid": "49b3e7623abc...",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {
                            "name": "build",
                            "status": "COMPLETED",
                            "conclusion": "SUCCESS"
                          },
                          {
                            "name": "test",
                            "status": "COMPLETED",
                            "conclusion": "SUCCESS"
                          }
                        ]
                      }
                    }
                  ]
                }
              },
              {
                "oid": "c4f35260a...",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {
                            "name": "lint",
                            "status": "COMPLETED",
                            "conclusion": "FAILURE"
                          }
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
```

### Field Descriptions

**Commit (`history.nodes[]`)**:
- `oid` (String): 40-character commit SHA (e.g., `"49b3e7623abc..."`)

**CheckSuite (`checkSuites.nodes[]`)**:
- Represents a group of check runs (e.g., a GitHub Actions workflow run)
- Multiple check suites per commit are common (multiple workflows triggered)

**CheckRun (`checkRuns.nodes[]`)**:
- `name` (String): Human-readable check run name (e.g., `"build"`, `"test-unit"`)
- `status` (Enum): Execution status (see Status Values below)
- `conclusion` (Enum | null): Final result (only set if `status == COMPLETED`)

### Status Values

| Value | Description | Maps to REST API |
|-------|-------------|------------------|
| `QUEUED` | Check run queued, not started | `queued` |
| `IN_PROGRESS` | Check run currently executing | `in_progress` |
| `COMPLETED` | Check run finished (see `conclusion`) | `completed` |

### Conclusion Values (only set if `status == COMPLETED`)

| Value | Description | Icon | Maps to REST API |
|-------|-------------|------|------------------|
| `SUCCESS` | Check passed | ✅ | `success` |
| `FAILURE` | Check failed | ❌ | `failure` |
| `NEUTRAL` | Check completed neutrally | ➖ | `neutral` |
| `CANCELLED` | Check was cancelled | 🚫 | `cancelled` |
| `SKIPPED` | Check was skipped | ➖ | `skipped` |
| `TIMED_OUT` | Check exceeded time limit | ❌ | `timed_out` |
| `ACTION_REQUIRED` | Manual intervention needed | ❌ | `action_required` |
| `STALE` | Check result is outdated | ➖ | `stale` |
| `null` | No conclusion (check still running) | 🕓 | `""` (empty) |

### Error Response (Schema Not Supported)

```json
{
  "errors": [
    {
      "type": "NOT_FOUND",
      "path": ["repository", "ref", "target", "checkSuites"],
      "locations": [{"line": 7, "column": 15}],
      "message": "Field 'checkSuites' doesn't exist on type 'Commit'"
    }
  ]
}
```

**Handling**: Detect `errors` key, fall back to REST API

### Error Response (Repository Not Found)

```json
{
  "data": {
    "repository": null
  },
  "errors": [
    {
      "type": "NOT_FOUND",
      "path": ["repository"],
      "message": "Could not resolve to a Repository with the name 'nonexistent-repo'."
    }
  ]
}
```

**Handling**: Exit with error message (same as current behavior)

### Error Response (Branch Not Found)

```json
{
  "data": {
    "repository": {
      "ref": null
    }
  }
}
```

**Handling**: Exit with error message "Branch not found: $BRANCH"

### Partial Response (Commit with No Check Suites)

```json
{
  "oid": "a390e5998...",
  "checkSuites": {
    "nodes": []
  }
}
```

**Handling**: Treat as zero check runs, display `❔` icon

## Pagination

**Current Limits**:
- `history(first: $limit)`: Fetch up to `$limit` commits (user-specified, default 15)
- `checkSuites(first: 100)`: Fetch up to 100 check suites per commit
- `checkRuns(first: 100)`: Fetch up to 100 check runs per suite

**Pagination Not Implemented** (initial version):
- If commit has >100 check suites: only first 100 fetched
- If check suite has >100 check runs: only first 100 fetched
- Known limitation documented in README.md

**Future Enhancement** (pagination with cursors):
```graphql
checkSuites(first: 100, after: $checkSuitesCursor) {
  pageInfo {
    hasNextPage
    endCursor
  }
  nodes { ... }
}
```

## Usage in Bash

### Inline Query (Recommended)

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
}
' -f owner="$OWNER" -f repo="$REPO" -f branch="refs/heads/$BRANCH" -F limit="$LIMIT"
```

**Flags**:
- `-f` (string): Pass string variables (`owner`, `repo`, `branch`)
- `-F` (raw): Pass non-string variables (`limit` as integer)

### With Timeout Wrapper

```bash
GRAPHQL_RESPONSE=$(run_with_timeout "$API_TIMEOUT" gh api graphql -f query='...' -f owner="$OWNER" -f repo="$REPO" -f branch="refs/heads/$BRANCH" -F limit="$LIMIT" 2>&1)

if [[ $? -ne 0 ]]; then
  echo "[GraphQL error or timeout]" >&2
  # Fall back to REST API
fi
```

## Response Transformation

### Extract TSV Format (for compatibility with existing aggregation logic)

```bash
jq -r '
  .data.repository.ref.target.history.nodes[] as $commit |
  $commit.oid as $sha |
  (
    $commit.checkSuites.nodes[]? |
    .checkRuns.nodes[]? |
    [$sha, .name, (.status // "" | ascii_downcase), (.conclusion // "" | ascii_downcase)]
  ) |
  @tsv
' <<< "$GRAPHQL_RESPONSE"
```

**Output Example**:
```
49b3e7623abc...	build	completed	success
49b3e7623abc...	test	completed	success
c4f35260a...	lint	completed	failure
```

**Format**: `SHA<TAB>NAME<TAB>status<TAB>conclusion`
- Matches existing REST API format: `NAME<TAB>status<TAB>conclusion`
- Added `SHA` prefix for grouping by commit

## Rate Limiting

**GraphQL vs REST**:
- REST API: Each commit = 1 API call (5000/hour limit = ~333 commits/hour at limit=15)
- GraphQL API: All commits = 1 API call (5000/hour limit = ~75,000 commits/hour at limit=15)

**Cost Calculation** (GitHub GraphQL cost model):
- Base query cost: 1 point
- `history(first: 15)`: +15 points
- `checkSuites(first: 100)` per commit: +100 points × 15 commits = 1500 points
- Total: ~1516 points per query (well under 5000 point rate limit per hour)

**Note**: GraphQL cost is not 1:1 with REST calls, but still significant improvement in overall efficiency.

## Testing

### Mock GraphQL Response (Success + Failure + Pending)

```json
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
                          {"name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"},
                          {"name": "test", "status": "IN_PROGRESS", "conclusion": null}
                        ]
                      }
                    }
                  ]
                }
              },
              {
                "oid": "def456",
                "checkSuites": {
                  "nodes": [
                    {
                      "checkRuns": {
                        "nodes": [
                          {"name": "lint", "status": "COMPLETED", "conclusion": "FAILURE"}
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
```

**Expected Transformation**:
```
abc123	build	completed	success
abc123	test	in_progress
def456	lint	completed	failure
```

**Expected Icons**:
- `abc123`: 🕓 (pending test run)
- `def456`: ❌ (failed lint)

### Mock GraphQL Error Response

```json
{
  "errors": [
    {
      "message": "Field 'checkSuites' doesn't exist on type 'Commit'",
      "locations": [{"line": 7, "column": 15}]
    }
  ]
}
```

**Expected Behavior**: Fall back to REST API, display results normally

## Compatibility Notes

**GitHub.com**: Fully supported (GraphQL v4 API stable)

**GitHub Enterprise Server**:
- GHES 3.4+: Supported (`checkSuites` field available on `Commit` type)
- GHES 3.0-3.3: Not supported (fallback to REST API automatically)
- GHES <3.0: Not supported (fallback to REST API automatically)

**Token Scopes**:
- Same as REST API: `repo` scope for private repositories
- No additional scopes required for GraphQL

## References

- [GitHub GraphQL API Explorer](https://docs.github.com/en/graphql/overview/explorer)
- [CheckSuite Object Schema](https://docs.github.com/en/graphql/reference/objects#checksuite)
- [CheckRun Object Schema](https://docs.github.com/en/graphql/reference/objects#checkrun)
- [GitHub CLI GraphQL Usage](https://cli.github.com/manual/gh_api)
