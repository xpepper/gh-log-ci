# Development Workflow

**Context Marker**: When working with this file, add `🧑‍💻` to your start-of-message markers.

**Example**:
"🍀 🧑‍💻 I'm working on the development workflow of gh-log-cli"

## Active Technologies

- Bash 4.0 or newer (the script exits with an actionable error on older shells, including
  macOS's default Bash 3.2 — install a current Bash with `brew install bash`)
- `gh` CLI (GitHub CLI)
- `git`
- `jq` (JSON processor via gh)

## Testing

- **Shellcheck**: Static analysis for Bash scripts
- **Bats**: Behavioral testing framework
- **Test files**: Located in `tests/` directory

## Common Commands

```bash
# Run all tests
make test

# Run local CI script
make ci-local

# Run the script
make run
```

## Development Rules

- Before committing, run `make test` to ensure all tests pass.
- Try to not mix in the same commit two different types of changes (e.g., refactorings and feats), as this makes it harder to review and understand the changes, and to assess the risk related to releasing them.
- Prefer creating a focused pull request (PR) instead of pushing directly to the main branch.
- Always update the README and this file when adding features or changing behavior.
- Don't forget to update the version in the script header when releasing a new version.

## Versioning

`VERSION` in the `gh-log-ci` header follows MAJOR.MINOR.PATCH:

- **MAJOR**: breaking CLI changes (flag removals, output format changes)
- **MINOR**: new features (new flags, new capabilities)
- **PATCH**: bug fixes, performance improvements, other non-breaking changes

Add a matching row to the README changelog in the same PR that bumps the version.

## CI/CD

- GitHub Actions workflow in `.github/workflows/ci.yml`
- Runs on pushes to master/main and pull requests
- Executes shellcheck and bats tests on Ubuntu
