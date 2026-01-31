# gh-log-ci Development Guidelines

## Project Overview

gh-log-ci is a GitHub CLI extension that displays CI status next to commit logs. It shows recent commits with inline summary icons indicating GitHub Check/Actions status (green, failing, pending, or cancelled).

- **Commit SHA mode**: Display CI status for a single specific commit by providing SHA as argument

## Architecture

- **Single Bash script**: The entire functionality is in `gh-log-ci` (753 lines)
- **GitHub API integration**: Uses GraphQL API v4 for batch queries (explicit REST API v3 mode via `--use-rest`)
- **Caching system**: Success-only caching with TTL to reduce API calls
- **Parallel processing**: Configurable concurrency for REST API mode
- **Watch mode**: Continuous polling with configurable intervals

### API Strategy
- **Primary: GraphQL batch query**: Single query fetches all commit check statuses (lines 221-290)
  - Query structure: Repository → Ref → Target → History(limit) → CheckSuites(100) → CheckRuns(100)
  - Reduces API calls from N to 1 (93% reduction for 15 commits)
  - Transformation: GraphQL JSON → jq → TSV → existing aggregation logic
  - **When to use**: Default mode, optimal for GitHub.com and GitHub Enterprise Server ≥ 3.4
- **REST API mode**: Per-commit API calls with concurrency control (lines 432-553)
  - Manual override: `--use-rest` flag or `LOG_CI_FORCE_REST=1` environment variable
  - **When to use**:
    - GitHub Enterprise Server < 3.4 (GraphQL Checks API unavailable)
    - Commits with >100 check suites (GraphQL query limit)
    - GraphQL API errors or timeouts
    - Debugging or comparing GraphQL vs REST behavior
  - Concurrency controlled via `--concurrency` flag (default: 4 parallel requests)
- **Error handling**: GraphQL errors fail fast with clear error messages suggesting `--use-rest` flag
- **Response handling**: Both APIs use identical status aggregation and icon mapping logic

## Development Workflow

### Active Technologies

- Bash (compatible with `/usr/bin/env bash`)
- `gh` CLI (GitHub CLI)
- `git`
- `jq` (JSON processor via gh)

### Web Search via Perplexity CLI

When you need to search the web, look up documentation, research a topic, or answer a question that requires up-to-date information, use the `llm` CLI with the Perplexity plugin instead of MCP tools.

**Prerequisites:**
- Install the `llm` CLI: `pip install llm` (or `brew install llm`)
- Install the Perplexity plugin: `llm install llm-perplexity`
- Configure API key: `llm keys set perplexity` (paste your Perplexity API key when prompted)
- Verify setup: `llm -m sonar 'hello'` should return a response

**Usage:**
```bash
# General web search / questions
llm -m sonar 'your question here'

# More thorough answers (flagship model, 200k context)
llm -m sonar-pro 'your question here'

# Deep research on complex topics
llm -m sonar-deep-research 'your complex research question'

# Reasoning-heavy questions
llm -m sonar-reasoning 'your reasoning question'
```

**Model selection guide:**
- `sonar` — Default choice for quick lookups and general questions
- `sonar-pro` — Use when you need more thorough or detailed answers
- `sonar-deep-research` — Use for complex multi-faceted research
- `sonar-reasoning` / `sonar-reasoning-pro` — Use when the question requires step-by-step reasoning

**When to use:**
- Looking up current documentation, APIs, or library versions
- Researching error messages or unfamiliar technologies
- Verifying facts or checking for recent changes
- Any question where your training data may be outdated

**Do NOT use for:**
- Questions answerable from the local codebase (use grep/read instead)
- Tasks that don't require web knowledge

### Testing
- **Shellcheck**: Static analysis for Bash scripts
- **Bats**: Behavioral testing framework
- **Test files**: Located in `tests/` directory

### Common Commands
```bash
# Run all tests
make test

# Run local CI script
make ci-local

# Run the script
make run
```

### Development Rules
- Before committing, run `make test` to ensure all tests pass.
- Use conventional commit messages (e.g., `feat:`, `refactor:`, `fix:`, `docs:`) to categorize changes.
  - Use `refactor:` for structural changes that do not add features or fix bugs.
  - Use `feat:` for behavioral changes or new features.
  - Use `style:` for formatting changes.
  - Use `test:` for adding or modifying tests.
  - Use `fix:` for bug fixes.
  - Use `docs:` for documentation updates.
  - Use `chore:` for changes to configuration files and scripts.
- Try to not mix in the same commit two different types of changes (e.g., refactorings and feats), as this makes it harder to review and understand the changes, and to assess the risk related to releasing them.
- Prefer creating a focused pull request (PR) instead of pushing directly to the main branch.
- Always update the README and this file when adding features or changing behavior.
- Don't forget to update the version in the script header when releasing a new version.

### CI/CD
- GitHub Actions workflow in `.github/workflows/ci.yml`
- Runs on pushes to master/main and pull requests
- Executes shellcheck and bats tests on Ubuntu

## Key Components

### Main Script (`gh-log-ci`)
- **Argument parsing**: Lines 70-119 handle CLI flags and environment variables
- **Commit SHA detection**: Lines 156-167 detect and validate commit SHAs
- **Branch detection**: Lines 169-185 auto-detect branch using GitHub API and git fallbacks (skipped in commit mode)
- **Remote URL parsing**: Lines 194-202 extract owner/repo from GitHub URLs
- **GraphQL functions**: Lines 221-290 handle batch query, transformation, and grouping
  - `fetch_checks_graphql()`: Execute GraphQL batch query with timeout
  - `transform_graphql_response()`: Convert nested JSON to TSV format
  - `group_by_sha()`: Extract check runs for specific commit SHA
  - `fetch_checks_graphql_commit()`: Execute GraphQL query for single commit (lines 293-334)
  - `transform_graphql_response_commit()`: Convert single commit JSON to TSV format (lines 336-348)
- **Cache management**: Lines 310-323 read cache with TTL validation
- **Main loop integration**: Lines 303-622 GraphQL or REST mode (controlled by --use-rest flag)
- **Status aggregation**: Shared logic reused for both GraphQL and REST responses
- **Watch mode**: Lines 624-635 implement continuous polling

### Caching System
- **Success-only caching**: Only caches successful commits (line 336)
- **Cache validation**: Requires all three conditions: `OVERALL_ICON=="✅"` AND `RAW_LINES!="__TIMEOUT__"` AND `pending_count==0`
- **Pending check exclusion**: Commits with ANY pending check runs are never cached (prevents incorrect success icon display)
- **TTL-based**: Configurable cache lifetime (default 24 hours)
- **Cache directory**: `~/.cache/gh-log-ci/` or configurable via `LOG_CI_CACHE_DIR`
- **Cache bypass**: `--no-cache` flag forces fresh API calls

### Commit SHA Mode
- **SHA detection**: Lines 156-167 detect and validate commit SHAs
- **Single commit GraphQL**: `fetch_checks_graphql_commit()` and `transform_graphql_response_commit()` functions
- **Conditional logic**: `IS_COMMIT_MODE` flag controls branch vs commit mode throughout script

### Event-Based Filtering
- **Purpose**: Exclude non-push workflows from status aggregation while keeping them visible
- **Implementation**: Add EXCLUDED flag (5th TSV column) based on `workflowRun.event != "push"`
- **Display behavior**: Excluded checks shown with 🤖 icon and `[non-push]` label when using `-C`
- **Aggregation**: Checks with EXCLUDED=1 skipped when computing overall status icon
- **GraphQL functions**: `transform_graphql_response()` and `transform_graphql_response_commit()`
- **REST mode limitation**: All checks marked EXCLUDED=0 (event types not available in REST API)
- **Matching behavior**: Aligns with GitHub's `statusCheckRollup` logic (only includes push events)

### Testing Structure
- **help.bats**: Tests CLI help and argument validation
- **cache_success.bats**: Tests caching functionality
- **timeout.bats**: Tests API timeout handling
- **watch_flags.bats**: Tests watch mode functionality
- **pending_icon.bats**: Tests pending status display and cache validation (prevents bug where pending builds showed ✅)
- **graphql_batch.bats**: Tests GraphQL query construction, transformation, and fallback behavior
- **commit_sha.bats**: Tests commit SHA detection, validation, and status display
- **event_filter.bats**: Tests event-based filtering logic in jq transformations

## Environment Variables

- `LOG_CI_LIMIT`: Number of commits to display (default: 15)
- `LOG_CI_CONCURRENCY`: Parallel API calls (default: 4)
- `LOG_CI_SHOW_CHECKS`: Show per-check run summaries (default: 0)
- `LOG_CI_NO_SPINNER`: Disable loading spinner (default: 0)
- `LOG_CI_API_TIMEOUT`: Max seconds per API request (default: 30)
- `LOG_CI_WATCH_INTERVAL`: Seconds between polls in watch mode (default: 10)
- `LOG_CI_CACHE_TTL`: Cache TTL in seconds (default: 86400)
- `LOG_CI_CACHE_DIR`: Cache directory path
- `LOG_CI_CACHE_DEBUG`: Enable cache debugging output
- `LOG_CI_FORCE_REST`: Force REST API mode (default: 0, set to 1 to bypass GraphQL)

## Important Implementation Details

- Uses `git log` with custom format for commit display (line 196)
- Implements timeout handling for API calls (lines 198-218)
- Progress spinner shows completed/total count (lines 253-266)
- Status aggregation logic prioritizes failures over pending over success (lines 318-326)
- Watch mode clears screen between iterations (lines 367-368)

## Development Notes

- The script requires GitHub CLI (`gh`) to be installed and authenticated
- All API calls go through `gh api` command
- Cache files are named `{owner}_{repo}_success.cache`
- Temporary directories are created for parallel processing output
- The script handles both remote and local branch scenarios
