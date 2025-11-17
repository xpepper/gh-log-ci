<!--
SYNC IMPACT REPORT
==================
Version: 0.0.0 → 1.0.0 (Initial constitution establishment)
Date: 2025-11-17

Modified Principles:
  - All principles newly established (first version)

Added Sections:
  - Core Principles (5 principles)
  - Technical Standards
  - Development Workflow
  - Governance

Templates Status:
  ✅ plan-template.md - Updated Constitution Check with all 5 principles
  ✅ spec-template.md - Reviewed, already aligned with test requirements
  ✅ tasks-template.md - Updated test section to enforce Test-First principle and align with gh-log-ci stack (Bats, Shellcheck)
  ✅ tasks-template.md - Updated implementation section to reflect single-script architecture and documentation requirements
  ⚠️ checklist-template.md - Not updated (optional/generic template)
  ⚠️ agent-file-template.md - Not updated (generic template, no constitution-specific content)

Follow-up Actions:
  - None - Initial version complete with template synchronization
-->

# gh-log-ci Constitution

## Core Principles

### I. Test-First Development (NON-NEGOTIABLE)

All changes MUST be tested before commit. Tests are executed via `make test` which runs:
- **Shellcheck**: Static analysis for Bash script quality
- **Bats**: Behavioral tests covering CLI flags, caching, timeouts, watch mode

**Rationale**: As a CLI tool relied upon by developers, regressions in gh-log-ci directly impact user workflows. Test-first development ensures stability and prevents breaking changes from reaching users.

### II. Conventional Commits

All commits MUST follow conventional commit format with appropriate type prefixes:
- `feat:` - New features or behavioral changes
- `fix:` - Bug fixes
- `refactor:` - Structural changes without behavioral changes
- `test:` - Test additions or modifications
- `docs:` - Documentation updates
- `style:` - Formatting changes
- `chore:` - Configuration and tooling changes

Each commit MUST contain only one type of change. Mixed-type commits (e.g., refactoring + feat) are prohibited.

**Rationale**: Clear commit history enables accurate risk assessment, easier code review, and simplified changelog generation. Single-type commits allow granular rollback if issues are discovered.

### III. Pull Request Discipline

Changes MUST be delivered via focused pull requests rather than direct pushes to master. Each PR MUST:
- Address a single concern or feature
- Pass all tests (`make test`)
- Include documentation updates if behavior changes
- Have a clear, reviewable scope

**Rationale**: Pull requests enable peer review, maintain quality gates, and provide discussion context. This is critical for a tool that integrates with GitHub's API where API contract changes or authentication issues could break user workflows.

### IV. Documentation Currency

When features or behavior change, the following MUST be updated in the same commit/PR:
- `README.md` - User-facing documentation, usage examples, flags
- `AGENTS.md` - Development context, architecture, implementation details
- Script version in `gh-log-ci` header (line 6: `VERSION="x.y.z"`)

**Rationale**: gh-log-ci is a CLI extension where the README is the primary interface documentation. Outdated docs lead to user confusion and support burden. AGENTS.md ensures development continuity.

### V. Single-Script Architecture

The entire implementation MUST remain in a single Bash script (`gh-log-ci`). Features MUST NOT be extracted into separate files or libraries unless the single-file constraint becomes demonstrably unmaintainable (>2000 lines with no clear organization).

**Rationale**: As a `gh` CLI extension, single-file distribution simplifies installation (`gh extension install`) and reduces dependency management. Users get a self-contained tool without module loading or PATH complexity.

## Technical Standards

**Language**: Bash (compatible with `/usr/bin/env bash`)
**Dependencies**:
- `gh` (GitHub CLI) - MUST be installed and authenticated
- `git` - For local repository operations
- Standard Unix utilities: `curl`, `jq` (via gh), `date`, `mktemp`

**Performance Requirements**:
- API timeout configurable (default 30s, `--api-timeout`)
- Parallel processing with concurrency limit (default 4, `--concurrency`)
- Caching for successful checks (TTL: 24h, configurable via `LOG_CI_CACHE_TTL`)

**Error Handling**:
- Use `set -euo pipefail` for strict error propagation
- API failures MUST show ⏲ icon with timeout indication
- Cache failures MUST fall back to fresh API calls

## Development Workflow

**Pre-Commit Requirements**:
1. Run `make test` - All tests MUST pass
2. Verify conventional commit message format
3. Ensure documentation updated if needed

**Testing Strategy**:
- **Static Analysis**: Shellcheck catches syntax and common errors
- **Behavioral Tests**: Bats tests cover:
  - `help.bats` - CLI help and argument validation
  - `cache_success.bats` - Caching functionality
  - `timeout.bats` - API timeout handling
  - `watch_flags.bats` - Watch mode functionality

**CI/CD**:
- GitHub Actions workflow (`.github/workflows/ci.yml`)
- Triggers: Pushes to master/main, pull requests
- Runs shellcheck + bats on Ubuntu

**Versioning**:
- Format: MAJOR.MINOR.PATCH (e.g., `0.5.0`)
- MAJOR: Breaking CLI changes (flag removals, output format changes)
- MINOR: New features (new flags, new capabilities)
- PATCH: Bug fixes, performance improvements, non-breaking changes

## Governance

This constitution supersedes all other development practices for gh-log-ci. All pull requests MUST comply with these principles before merge.

**Amendment Process**:
1. Proposed changes MUST be documented in a PR
2. Rationale for amendment MUST be provided
3. Impact on existing workflows MUST be assessed
4. Version bump according to change scope (MAJOR for principle removal/redefinition, MINOR for additions, PATCH for clarifications)

**Compliance Review**:
- Every PR reviewer MUST verify constitution compliance
- Deviations MUST be explicitly justified and documented in PR description
- Repeated violations trigger constitution review and potential amendment

**Runtime Guidance**:
- Development context and implementation details are maintained in `AGENTS.md`
- User-facing documentation and usage are maintained in `README.md`
- This constitution governs process and principles, not implementation specifics

**Version**: 1.0.0 | **Ratified**: 2025-11-17 | **Last Amended**: 2025-11-17
