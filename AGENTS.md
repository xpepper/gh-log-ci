# gh-log-ci Development Guidelines

## Project Overview

gh-log-ci is a GitHub CLI extension that displays CI status next to commit logs. It shows recent commits with inline summary icons indicating GitHub Check/Actions status (green, failing, pending, or cancelled).

- **Commit SHA mode**: Display CI status for a single specific commit by providing SHA as argument

## Quick Reference

**Commands:**
```bash
make test         # Run all tests
make ci-local     # Run local CI script
make run          # Run the extension
./gh-log-ci       # Direct execution
```

**Technologies:**
- Bash (single script, 753 lines)
- GitHub CLI (`gh`)
- GraphQL API v4 (primary) or REST API v3 (`--use-rest`)

## Detailed Guidelines

For specific topics, see:

- [Architecture](.claude/architecture.md) - Technical implementation, API strategy, caching, event filtering
- [Development Workflow](.claude/development.md) - Development rules, CI/CD, common commands
- [Testing](.claude/testing.md) - Test structure, environment variables
- [Web Search](.claude/perplexity.md) - Using Perplexity CLI for research
