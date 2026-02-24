# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-02-24

### Added

- Voice interface: whisper.cpp offline STT + Piper TTS with `glados-stt`, `glados-tts`, `glados-voice` wrappers
- Internet access: self-hosted SearXNG meta-search engine via Docker Compose
- OpenClaw voice and web-search integration (`configure_openclaw_voice`, `configure_openclaw_websearch`)
- CLI flags: `--skip-audio`, `--skip-internet`, `--whisper-model`
- Modular library architecture (`lib/` directory with per-concern modules)
- Post-install health checks for audio and internet components

### Changed

- Installer refactored from single script into modular `lib/` structure
- README updated with full v3 component table, flags, and project structure
- Makefile `lint` target now includes `lib/*.sh`
- TOTAL_STEPS dynamically adjusted based on `--skip-*` flags

### Fixed

- Docker install now uses `secure_download_and_run` pattern instead of `curl | sudo sh`
- `--whisper-model` with invalid value now properly resets to default
- `cmake_flags` array expansion fixed to avoid word-splitting in `bash -c` context
- `ollama list` model matching tightened to prevent false prefix matches
- `refresh_path` no longer sources user shell profiles (avoids side effects)
- Telegram bot token passed via environment instead of CLI arg (not visible in `ps`)
- SearXNG `settings.yml` permissions restricted to `600` (contains secret key)
- Added integrity warning in `secure_download_and_run` for transparency

### Security

- Docker convenience script validated (shebang + non-empty) before execution with `sudo`
- SearXNG configuration files have restricted permissions
- Telegram token no longer exposed in process listing

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

[3.0.0]: https://github.com/j4ngx/glados_installer/compare/v2.0.0...v3.0.0
[2.0.0]: https://github.com/j4ngx/glados_installer/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/j4ngx/glados_installer/releases/tag/v1.0.0
