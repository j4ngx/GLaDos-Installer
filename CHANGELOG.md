# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-02-24

### Added

- Voice interface: whisper.cpp offline STT + Piper TTS with `glados-stt`, `glados-tts`, `glados-voice` wrappers
- Internet access: self-hosted SearXNG meta-search engine via Docker Compose
- OpenClaw voice and web-search integration (`configure_openclaw_voice`, `configure_openclaw_websearch`)
- Static IP configuration: auto-detect primary interface, supports nmcli / ifupdown / netplan backends
- Swap file management: auto-sized for LLM workloads (match RAM, cap 8 GB, `vm.swappiness=10`)
- GPU acceleration: auto-detect NVIDIA (Container Toolkit) and AMD (ROCm), Docker GPU passthrough
- UFW firewall: deny-by-default policy, SSH rate limiting, configurable SSH port
- System hardening: SSH drop-in config, unattended security upgrades, log rotation, hostname/timezone setup
- Cron-based health monitoring: checks Ollama, OpenClaw, SearXNG, Docker every 5 minutes with alerting
- Backup/restore/uninstall utilities: full config export to `tar.gz`, numbered restore selection, safe uninstall
- CLI flags: `--skip-audio`, `--skip-internet`, `--whisper-model`, `--piper-voice`
- CLI flags: `--static-ip`, `--static-gw`, `--static-dns`, `--static-mask`, `--skip-static-ip`
- CLI flags: `--swap-size`, `--skip-swap`
- CLI flags: `--skip-gpu`
- CLI flags: `--ssh-port`, `--skip-firewall`
- CLI flags: `--hostname`, `--timezone`, `--skip-hardening`
- CLI flags: `--skip-healthcheck`
- CLI flags: `--backup`, `--restore [file]`, `--uninstall`
- CLI flags: `--http-proxy`, `--https-proxy`
- Modular library architecture (`lib/` directory with 17 per-concern modules)
- 4-phase installation pipeline: system foundations → core services → optional features → server hardening
- Post-install health checks for all components (audio, internet, swap, GPU, firewall, hardening, healthcheck)
- Interactive installation plan review showing all enabled/skipped features
- Proxy support: `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` environment variables and CLI flags
- `--status` now reports on all 17 modules (static IP, swap, GPU, firewall, hardening, healthcheck, Docker)
- Source-guard pattern (`_GLADOS_*_LOADED`) prevents double-sourcing of library modules
- Piper TTS multi-voice support: 8 curated voices (en_US/en_GB, male/female, various qualities)
- Build artifact cleanup for whisper.cpp (~500 MB savings)

### Changed

- Installer refactored from single script into modular `lib/` structure (17 modules)
- README completely rewritten with full v3 component table, 30+ CLI flags, module details, and updated project structure
- Makefile `lint` target now includes `lib/*.sh`
- TOTAL_STEPS dynamically adjusted based on all `--skip-*` flags (up to 17 steps)
- Pre-flight checks expanded: audio hardware detection, dependency version checks
- Interactive review screen shows all configurable features with current values

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
- SearXNG containers bound to `127.0.0.1` only with `cap_drop: ALL`
- Telegram token no longer exposed in process listing
- UFW firewall configured with deny-by-default policy and SSH brute-force rate limiting
- SSH hardening: disabled root login, disabled X11/agent forwarding, max 3 auth tries
- Unattended security upgrades enabled automatically
- Swap file created with `chmod 600` (restricted permissions)
- Static IP backup created before network changes

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
