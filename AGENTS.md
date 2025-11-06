# AGENTS.md

## Project Overview

gh-log-ci is a GitHub CLI extension that displays CI status next to commit logs. It shows recent commits with inline summary icons indicating GitHub Check/Actions status (green, failing, pending, or cancelled).

## Architecture

- **Single Bash script**: The entire functionality is in `gh-log-ci` (lines 1-378)
- **GitHub API integration**: Uses `gh api` to fetch check runs for each commit
- **Caching system**: Success-only caching with TTL to reduce API calls
- **Parallel processing**: Configurable concurrency for API calls
- **Watch mode**: Continuous polling with configurable intervals

## Development Workflow

### Testing
- **Shellcheck**: Static analysis for Bash scripts
- **Bats**: Behavioral testing framework
- **Test files**: Located in `tests/` directory

### Common Commands
```bash
# Run all tests
make test

# Run shellcheck only
make shellcheck

# Run bats tests only
make bats

# Run local CI script
make ci-local

# Install dependencies (macOS)
make install-deps-macos

# Install dependencies (Ubuntu)
make install-deps-ubuntu

# Clean cache
make clean-cache

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
- **Branch detection**: Lines 146-162 auto-detect branch using GitHub API and git fallbacks
- **Remote URL parsing**: Lines 171-179 extract owner/repo from GitHub URLs
- **Cache management**: Lines 234-248 read cache, lines 334-338 write cache
- **Parallel processing**: Lines 274-350 handle concurrent API calls with configurable limits
- **Status mapping**: Lines 290-326 map GitHub check statuses to emoji icons
- **Watch mode**: Lines 365-378 implement continuous polling

### Caching System
- **Success-only caching**: Only caches successful commits (line 334)
- **TTL-based**: Configurable cache lifetime (default 24 hours)
- **Cache directory**: `~/.cache/gh-log-ci/` or configurable via `LOG_CI_CACHE_DIR`
- **Cache bypass**: `--no-cache` flag forces fresh API calls

### Testing Structure
- **help.bats**: Tests CLI help and argument validation
- **cache_success.bats**: Tests caching functionality
- **timeout.bats**: Tests API timeout handling
- **watch_flags.bats**: Tests watch mode functionality

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

## Important Implementation Details

- Uses `git log` with custom format for commit display (line 193)
- Implements timeout handling for API calls (lines 195-215)
- Progress spinner shows completed/total count (lines 253-266)
- Status aggregation logic prioritizes failures over pending over success (lines 318-326)
- Watch mode clears screen between iterations (lines 367-368)

## Development Notes

- The script requires GitHub CLI (`gh`) to be installed and authenticated
- All API calls go through `gh api` command
- Cache files are named `{owner}_{repo}_success.cache`
- Temporary directories are created for parallel processing output
- The script handles both remote and local branch scenarios
