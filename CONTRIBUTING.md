# Contributing to GLaDOS Installer

Thank you for your interest in contributing! This document provides guidelines to make the process smooth for everyone.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to uphold this standard.

## How Can I Contribute?

### Reporting Bugs

- Check existing [issues](https://github.com/j4ngx/glados_installer/issues) to avoid duplicates
- Use the **Bug Report** issue template
- Include your OS, architecture, and relevant log output

### Suggesting Features

- Open a **Feature Request** issue
- Explain the use case and expected behaviour

### Submitting Code

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/your-feature`
3. Make your changes
4. Run linting: `make lint`
5. Commit using [Conventional Commits](#commit-messages)
6. Push and open a Pull Request

## Development Setup

### Prerequisites

- **Bash** 4.4+
- **[ShellCheck](https://www.shellcheck.net/)** for static analysis
- **GNU Make** (optional, for shortcuts)

### Install ShellCheck

```bash
# Debian/Ubuntu
sudo apt-get install shellcheck

# macOS
brew install shellcheck

# Or use Docker
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable glados_installer.sh
```

### Running Lint

```bash
# Using Make (lints main script + all lib modules)
make lint

# Directly
shellcheck -x -s bash glados_installer.sh lib/*.sh
```

### Dry-Run Testing

```bash
# Preview without changes
./glados_installer.sh --dry-run --verbose

# Minimal preview (skip heavy optional features)
./glados_installer.sh --dry-run --skip-audio --skip-internet --skip-telegram --skip-gpu
```

## Coding Standards

### Shell Script Guidelines

- **ShellCheck clean** — all code must pass `shellcheck -x -s bash` with no errors
- **Use `set -Eeuo pipefail`** — strict error handling
- **Quote all variables** — `"$var"` not `$var`
- **Use `[[ ]]`** not `[ ]` for tests
- **Use `$(command)` not backticks** for command substitution
- **Functions** — keep them focused and under 50 lines
- **Comments** — explain *why*, not *what*

### Naming Conventions

| Entity | Convention | Example |
|--------|-----------|---------|
| Variables | `UPPER_SNAKE_CASE` | `OLLAMA_META_MODEL_TAG` |
| Local variables | `lower_snake_case` | `local disk_avail_mb` |
| Functions | `lower_snake_case` | `install_ollama()` |
| Constants | `readonly UPPER_SNAKE_CASE` | `readonly MIN_DISK_MB=10240` |

### Code Structure

The installer uses a **modular library architecture** with 17 modules in `lib/`. The main script (`glados_installer.sh`) sources all modules and orchestrates the 4-phase installation pipeline.

**Adding a new module:**

1. Create `lib/yourmodule.sh` following the source-guard pattern:
```bash
[[ -n "${_GLADOS_YOURMODULE_LOADED:-}" ]] && return
_GLADOS_YOURMODULE_LOADED=1
```

2. Export a main function and a health-check function:
```bash
###############################################################################
# Section Name
###############################################################################

configure_yourmodule() {
  section "Step description"

  # Check if already done (idempotent)
  if already_configured; then
    success "Already configured."
    return
  fi

  # Do the work
  spinner_start "Working..."
  run_cmd some_command
  spinner_stop

  success "Done."
}

check_yourmodule_health() {
  if condition_is_met; then
    echo -e "  ${GREEN}✔${NC}  YourModule      : healthy"
  else
    echo -e "  ${RED}✘${NC}  YourModule      : not running"
    return 1
  fi
}
```

3. Source it in `glados_installer.sh`:
```bash
_source_lib yourmodule.sh
```

4. Add a `--skip-yourmodule` flag in `parse_args()` and wire it into `main()`.

5. Add the health check to `run_health_check()` and `show_status()`.

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <gitmoji> <description>

[optional body]
```

### Types

| Type | Purpose |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no logic change |
| `refactor` | Code restructuring |
| `test` | Adding or updating tests |
| `ci` | CI/CD changes |
| `chore` | Maintenance tasks |

### Examples

```
feat(telegram): ✨ add webhook mode for Telegram integration
fix(ollama): 🐛 handle timeout when API is slow to start
docs: 📝 add troubleshooting section to README
ci: 🔧 add ShellCheck workflow for PRs
```

## Pull Request Process

1. **Ensure ShellCheck passes** — `make lint`
2. **Test on a clean Debian system** (or use `--dry-run`)
3. **Update documentation** if adding new flags or changing behaviour
4. **Update CHANGELOG.md** under `[Unreleased]`
5. **Link related issues** in the PR description
6. **Request review** from a maintainer

### PR Title Format

Use the same Conventional Commits format for PR titles:

```
feat(ollama): ✨ support custom Ollama host and port
```

---

Thank you for contributing! 🎉
