<p align="center">
  <img src="assets/gh-log-ci-banner.png" alt="gh-log-ci logo and example output" width="340">
</p>

<h1 align="center">gh-log-ci</h1>
<p align="center"><em>A GitHub CLI extension that shows CI status next to commit logs</em></p>

`gh-log-ci` is a GitHub CLI extension that augments the regular `git log` / `gh` experience by showing the Continuous Integration (CI) status for recent commits of a repository side-by-side with commit metadata. This helps developers quickly assess whether a given commit is "green" (safe to release) or has failing / pending checks.

## Why?
Looking at commit history alone doesn't tell you if the associated pipelines succeeded. Surfacing CI status inline speeds up:
- Release decisions (pick the latest green commit)
- Debugging (spot a series of failing commits)
- Code review follow-up (ensure post-merge checks passed)

## Features
- Shows last 15 commits of a branch (auto-detected default if no arg: GitHub's default branch, else falls back to `master`, `main`, or current HEAD) from the remote.
- Parses the associated GitHub check runs and derives an icon summarizing overall state.
- Works with any repo that has GitHub Actions or other GitHub Check providers.
- Colorized commit output identical to regular `git log --pretty` formatting.

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
| ✅ | At least one check run succeeded and no failures detected |
| ❌ | One or more check runs concluded with failure / timed_out / action_required |
| 🚫 | All check runs were cancelled |
| 🕓 | No check runs yet / still in progress / unknown state |
| ❔ | Fallback when state can't be determined |

## Installation
Prerequisites:
- GitHub CLI (`gh`) installed and authenticated (`gh auth login`).
- Bash (script uses Bash-specific features).

Install the extension locally (from the repository root):
```bash
gh extension install .
```
If you push this repository to GitHub you can also install via:
```bash
gh extension install <owner>/gh-log-ci
```

## Usage
List CI status for the repository's default branch:
```bash
gh log-ci
```
Specify a branch explicitly:
```bash
gh log-ci release-branch
```
Branch resolution when no argument is given:
1. `gh repo view --json defaultBranchRef` (GitHub default)
2. `master` if present
3. `main` if present
4. Current local HEAD branch name
Show help (not implemented yet; see roadmap below).

## How It Works
1. Detects the Git remote URL and extracts `OWNER` and `REPO`.
2. Fetches the specified branch from `origin`.
3. Uses `git log` to output last 15 commits with a tab-delimited format.
4. For each commit, calls the GitHub REST API: `/repos/{owner}/{repo}/commits/{sha}/check-runs`.
5. Aggregates conclusions of all check runs and maps them to a single icon.

## Configuration
Currently minimal:
- Branch: first CLI argument (auto-detects if omitted).
- Number of commits: fixed to 15 (will be configurable later).

## Limitations
- Multiple API calls (one per commit) may be slow for large histories.
- Doesn't differentiate between partial success (mixed checks) and all-green; first failure wins.
- Ignores pending vs in_progress nuance (both shown as 🕓).
- No pagination / only last 15 commits.
- No caching; repeated runs query API every time.
- Assumes `origin` remote; other naming conventions unsupported.

## Roadmap / Potential Improvements
- Make number of commits configurable (`--limit` or environment variable).
- Add `--branch` named flag and `--help` output.
- Support other remotes or auto-detect default branch via `gh repo view`.
- Aggregate status with more granular precedence (e.g., success only if all succeeded; mixed icon if partial failures).
- Parallelize API calls for performance (GNU parallel / xargs -P / background jobs) or use GraphQL batch queries.
- Add caching layer (e.g., store recent SHA -> status in temp file with short TTL).
- Handle rate limiting gracefully (backoff + message).
- Optional columns (author email, commit age like "2h ago").
- Output as JSON / markdown / table formats (`--format=json|text`).
- Support filtering by author or by conclusion state (e.g., only failed).
- Show workflow run URLs for quick navigation.
- Detect and display workflow names and individual statuses.
- Color-coded icons for dark/light terminals and accessible alternatives.
- Unit tests using bats or shellspec.
- Containerized distribution (e.g., `gh extension install docker://...`).

## Contributing
1. Fork and clone.
2. Create a feature branch.
3. Make changes + add tests (when available).
4. Open a PR.

## Troubleshooting
- "Could not detect Git remote URL": Ensure you are within a cloned GitHub repository and have an `origin` remote.
- Auth errors from `gh api`: Run `gh auth status` and log in.
- Empty statuses (lots of 🕓): CI might not have started yet or uses legacy statuses (check GitHub Actions tab).

## License
See `LICENSE`.

## Disclaimer
This is an early MVP; expect breaking changes as features evolve.
