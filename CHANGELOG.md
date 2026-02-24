# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-24

### Added

- Full installation pipeline: Ollama, OpenClaw, Docker, Telegram
- Pre-flight system checks (RAM, disk, CPU, network, architecture)
- Interactive configuration review with customisation prompts
- Non-interactive mode for unattended/automated installs
- Dry-run mode to preview actions without system changes
- Verbose/debug logging with ANSI-stripped log files
- ASCII art banner and coloured terminal output
- Spinner animations for long-running operations
- Lock file mechanism (flock or PID-based) to prevent concurrent runs
- Retry wrapper for network operations with configurable attempts
- Secure download helper that validates scripts before execution
- Post-install health verification for all components
- `--status` command for quick health overview
- Telegram bot token validation and secure handling
- CLI flags: `--model`, `--agent-name`, `--skip-telegram`, `--skip-onboard`
- Minimum version checks for curl, git, and Docker
- Comprehensive error handling with `set -Eeuo pipefail` and trap handlers

### Security

- Downloaded scripts validated before execution (shebang check, empty check)
- Telegram bot token cleared from process memory after configuration
- Token input hidden during interactive prompt (`read -s`)
- Lock file prevents race conditions from concurrent installs

## [1.0.0] - 2026-01-01

### Added

- Initial release with basic Ollama and OpenClaw installation

[2.0.0]: https://github.com/j4ngx/glados_installer/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/j4ngx/glados_installer/releases/tag/v1.0.0
