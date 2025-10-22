<p align="center">
  <img src="assets/gh-log-ci-banner.png" alt="gh-log-ci logo and example output" width="340">
</p>

<h1 align="center">gh-log-ci</h1>
<p align="center"><em>A GitHub CLI extension that shows CI status next to commit logs</em></p>

`gh log-ci` displays recent commits with an inline summary icon of their GitHub Check / Actions status so you can instantly see which commits are green, failing, pending, or cancelled.

## Quickstart

`gh log-ci` works with GitHub.com and GitHub Enterprise Server (any version that supports Checks API).

1. Install [GitHub CLI](https://cli.github.com/)
2. Authenticate: `gh auth login`
3. (Optional) Ensure you have access to private repos you care about
4. Install the extension: `gh extension install xpepper/gh-log-ci` (or `gh extension install .` from local checkout)
5. Run: `gh log-ci` on a GitHub repo
6. Profit! ✅ 🚀

## Usage

Basic usage (auto-detect default branch):
```shell
gh log-ci
```
Specify a branch explicitly:
```shell
gh log-ci release-branch
```
Branch resolution order when no argument is provided:
1. GitHub default branch (`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`)
2. `master` if present
3. `main` if present
4. Current local HEAD branch

### Flags
```
  --branch <name>        Use a specific branch (overrides auto-detect)
  --limit, -n <n>        Number of commits to display (default: 15; env LOG_CI_LIMIT)
  --concurrency, -c <n>  Parallel API calls (default: 4; env LOG_CI_CONCURRENCY)
  --checks, -C           Show per-check run summaries
  --help, -h          Show help / usage
  --version           Show version
```

Help example:
```shell
$ gh log-ci --help
gh log-ci - show CI status next to recent commits

Usage:
  gh log-ci [options] [<branch>]

Options:
  --branch <name>        Branch to inspect (alternative to positional <branch>)
  --limit, -n <n>        Number of commits to display (default: 15; env LOG_CI_LIMIT)
  --concurrency, -c <n>  Parallel API calls (default: 4; env LOG_CI_CONCURRENCY)
  --checks, -C           Show per-check run summaries
  --help, -h          Show this help text
  --version           Show version

Branch auto-detect order when <branch> not supplied:
  1. GitHub default branch (via gh repo view)
  2. master (if exists)
  3. main (if exists)
  4. current HEAD branch
```

## Output Example
```
$ gh log-ci

my-repo

Commit status for my-org/my-repo (master):
-----------------------------------------
✅  49b3e7623 - (HEAD -> master, origin/master, origin/HEAD) refactor(component): improve caching (Wed Oct 22 15:15:13 2025 +0200) <Jane Doe>
❌  c4f35260a - feat(auth): add MFA (Wed Oct 22 09:25:09 2025 +0200) <John Smith>
🕓  a390e5998 - chore(deps): bump library (Tue Oct 21 16:52:40 2025 +0200) <dependabot[bot]>
```

## Icons Legend
| Icon | Meaning |
|------|---------|
| ✅ | All completed check runs succeeded (no failures/pending) |
| ❌ | At least one failing/timed_out/action_required check run |
| 🕓 | One or more check runs still in progress / queued and no failures yet |
| 🚫 | All check runs cancelled (and none succeeded) |
| ⚠ | Mixed: successes and failures both present |
| ➖ | Neutral/skipped/stale (shown only in per-check detail) |
| ❔ | Fallback / unknown state |

## Features
| Capability | Description |
|------------|-------------|
| Auto branch | Detects default branch, falls back to master/main/HEAD |
| Status aggregation | Smarter overall icon (pending vs all-green vs mixed failure) |
| Per-check summaries | Optional detailed list via `--checks` / `LOG_CI_SHOW_CHECKS=1` |
| Parallel fetching | Concurrency-controlled API calls (`--concurrency`) |
| Colorized log | Mirrors `git log` pretty format with colors |
| Lightweight | Single Bash script, no external deps beyond `gh` |

## Permissions

`gh log-ci` uses the credentials configured via [`gh auth login`](https://cli.github.com/manual/gh_auth_login) or any supported `gh` environment variables. Required scopes depend on what you want to read:

Typical token (user) scopes:
- `repo` (private repository commit metadata & checks)
- `read:org` (if accessing private org repos)

GitHub App / server-to-server tokens need read access to:
- Repository Contents
- Repository Metadata
- Actions / Checks (implicitly via Checks API)

If you see authentication errors, re-run:
```shell
gh auth status
gh auth login
```

## How It Works
1. Determines branch (see order above).
2. Fetches commits from `origin/<branch>`.
3. Emits a tab-delimited `git log` for the last 15 commits.
4. For each commit, calls REST endpoint `/repos/{owner}/{repo}/commits/{sha}/check-runs`.
5. Maps combined conclusions to an icon and prints decorated line.

## Configuration (Current)
- Branch: positional argument or `--branch` (auto-detected if omitted).
- Commit count: `--limit` / `-n` (default 15) or environment `LOG_CI_LIMIT`.
- Concurrency: `--concurrency` / `-c` (default 4) or environment `LOG_CI_CONCURRENCY`.
- Per-check detail: `--checks` / `-C` or environment `LOG_CI_SHOW_CHECKS=1`.

## Limitations
- One REST API call per commit (future: GraphQL batch).
- Per-check summaries increase output size (consider piping/grep).
- Neutral/skipped/stale checks don't affect overall icon yet.
- No JSON / alternative formats yet.
- Assumes `origin` remote name.

## Roadmap
- Cache recent commit statuses (temp file TTL; invalidate on new HEAD, store results keyed by branch head SHA).
- Accessibility: `--no-emoji`, `--no-color` respecting `NO_COLOR`.
- Rate-limit handling with backoff + user notice.
- Add a "watch" mode to monitor new commits live. It should poll periodically and update the display.
- Commit age column (e.g., `2h ago`).
- GraphQL batch query to reduce API calls: use a single GraphQL batch query to fetch all check suite statuses.
- Implement the queued vs in_progress distinction next (would be a minor version bump)
- Replace temp files with mkfifo or captured descriptors for even less I/O (micro-optimization).
- Workflow names and URLs (opt-in with a flag).
- Filtering: author, status, date range, grep on commit message.
- Semantic versioning policy (documented in README).
- Output formats: `--format json`, `--format table`, `--format md`.

## Testing
We use [bats](https://github.com/bats-core/bats-core) for basic behavioral tests and [shellcheck](https://www.shellcheck.net/) for static analysis.

Run locally:
```bash
shellcheck gh-log-ci
bats tests
```
CI runs automatically on pushes / PRs (see `.github/workflows/ci.yml`). A badge can be added once the repository is public.

Convenience local CI script (runs both):
```bash
./ci-local.sh
```

## Contributing
1. Fork and clone.
2. Create a feature branch.
3. Make changes + add tests (when available).
4. Open a PR.

## Troubleshooting
| Issue | Suggestion |
|-------|------------|
| Remote URL error | Ensure you're inside a GitHub repo with an `origin` remote |
| Auth errors | Run `gh auth status` then `gh auth login` |
| All 🕓 icons | Checks not started yet or using legacy status API |
| Slow output | Limit commits or wait between runs to avoid rate limits |

## License
See `LICENSE`.

## Disclaimer
Early MVP; expect changes as features mature.
