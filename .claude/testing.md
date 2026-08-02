# Testing

**Context Marker**: When working with this file, add `💉` to your start-of-message markers.

**Example**:
"🍀 💉 I'm working on the testing suite of gh-log-cli"

## Test Structure

- **help.bats**: Tests CLI help and argument validation
- **cache_success.bats**: Tests caching functionality
- **timeout.bats**: Tests API timeout handling
- **watch_flags.bats**: Tests watch mode functionality
- **pending_icon.bats**: Tests pending status display and cache validation (prevents bug where pending builds showed ✅)
- **graphql_batch.bats**: Tests GraphQL query construction, transformation, and fallback behavior
- **commit_sha.bats**: Tests commit SHA detection, validation, and status display
- **event_filter.bats**: Tests event-based filtering logic in jq transformations
- **bash_version.bats**: Tests that the script fails with an actionable error on Bash < 4.0

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
- `LOG_CI_WATCH_ONCE`: Testing-only — run a single watch iteration then exit, so watch mode
  can be asserted without an infinite loop
