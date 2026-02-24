<p align="center">
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white" alt="Shell: Bash">
  <img src="https://img.shields.io/badge/platform-Debian%2013-A81D33?logo=debian&logoColor=white" alt="Platform: Debian 13">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/version-2.0.0-brightgreen" alt="Version: 2.0.0">
  <img src="https://github.com/j4ngx/glados_installer/actions/workflows/ci.yml/badge.svg" alt="CI">
</p>

<h1 align="center">
  <br>
  🤖 GLaDOS Installer
  <br>
</h1>

<p align="center">
  <strong>All-in-one installer for a local AI assistant stack on low-power hardware.</strong>
  <br>
  Ollama · OpenClaw · Telegram
</p>

---

## Overview

GLaDOS Installer is a professional, single-script installer that sets up a complete **local AI assistant environment** on Debian-based systems. It is specifically optimised for low-power hardware like the Intel N4000 with 8 GB RAM, but works on any compatible x86_64 or ARM64 machine.

**What gets installed:**

| Component | Description |
|-----------|-------------|
| **[Ollama](https://ollama.com)** | Local LLM runtime for running models on-device |
| **Meta Llama 3** | Default language model (configurable) |
| **[OpenClaw](https://openclaw.ai)** | Personal AI assistant with gateway and CLI |
| **Telegram Bot** | Optional Telegram integration for remote access |

## Features

- ✨ **Single command** — fully automated installation from scratch
- 🔒 **Secure downloads** — validates scripts before execution
- 🔄 **Idempotent** — safe to re-run; skips already-installed components
- 🎯 **Pre-flight checks** — validates RAM, disk, CPU, network before starting
- 🎨 **Beautiful CLI** — coloured output, spinners, progress tracking
- 🛡️ **Robust error handling** — `set -Eeuo pipefail`, trap handlers, lock files
- 📝 **Full logging** — timestamped logs saved to `~/glados-installer/logs/`
- ⚙️ **Configurable** — CLI flags for model, agent name, dry-run, and more
- 🤖 **Non-interactive mode** — unattended installs for automation
- 📊 **Status command** — check health of all components at a glance

## Requirements

| Requirement | Minimum |
|-------------|---------|
| **OS** | Debian 13 (other Debian-based distros may work) |
| **Architecture** | x86_64 or ARM64 |
| **RAM** | 4 GB (8 GB recommended) |
| **Disk** | 10 GB free space |
| **Network** | Internet access required for downloads |
| **Privileges** | `sudo` access |

### Dependencies (auto-installed)

`curl`, `wget`, `git`, `ca-certificates`, `gnupg`, `lsb-release`, `build-essential`, `cmake`, `libopenblas-dev`, `jq`, `Docker`

## Quick Start

```bash
# Clone the repository
git clone https://github.com/j4ngx/glados_installer.git
cd glados_installer

# Make the script executable
chmod +x glados_installer.sh

# Run the installer
./glados_installer.sh
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/j4ngx/glados_installer/master/glados_installer.sh | bash
```

> ⚠️ **Tip:** Always review scripts before piping to `bash`. You can download and inspect first:
> ```bash
> curl -fsSL -o glados_installer.sh https://raw.githubusercontent.com/j4ngx/glados_installer/master/glados_installer.sh
> less glados_installer.sh
> chmod +x glados_installer.sh && ./glados_installer.sh
> ```

## Usage

```
GLaDOS Installer v2.0.0

USAGE
  glados_installer.sh [OPTIONS]

OPTIONS
  --model <tag>         Ollama model tag (default: llama3)
                        Examples: llama3, llama3.1:instruct, phi3:mini
  --agent-name <name>   OpenClaw agent label (default: GLaDOS)
  --non-interactive     Skip interactive prompts where possible
  --skip-telegram       Skip Telegram channel configuration
  --skip-onboard        Skip 'openclaw onboard' wizard (run manually later)
  --dry-run             Show what would be done without making changes
  --verbose             Enable debug-level output
  --status              Show current installation status and exit
  --help, -h            Show this help message and exit

ENVIRONMENT VARIABLES
  TELEGRAM_BOT_TOKEN    Telegram bot token (export before running)
```

### Examples

```bash
# Basic install with all defaults
./glados_installer.sh

# Custom model and agent name
./glados_installer.sh --model phi3:mini --agent-name "Jarvis"

# Install with Telegram bot
export TELEGRAM_BOT_TOKEN="123456:ABCdef..."
./glados_installer.sh

# Preview without making changes
./glados_installer.sh --dry-run --verbose

# Fully automated (no prompts)
./glados_installer.sh --non-interactive --skip-telegram

# Check health status of existing installation
./glados_installer.sh --status
```

## Installation Steps

The installer executes the following steps in order:

```
[1/8]  Pre-flight system checks
[2/8]  Installing base system packages
[3/8]  Docker runtime
[4/8]  Ollama installation
[5/8]  Pulling Ollama model
[6/8]  OpenClaw installation
[7/8]  OpenClaw onboarding wizard        (skippable)
[8/8]  Telegram channel configuration    (skippable)
```

Each step includes health checks and graceful error recovery.

## Post-Installation

After a successful install, you can interact with your stack:

```bash
# Check Ollama
ollama list
curl http://127.0.0.1:11434/api/tags

# Check OpenClaw
openclaw status
openclaw gateway status
openclaw health
openclaw dashboard   # opens http://127.0.0.1:18789/

# Telegram pairing (if configured)
openclaw channels status
openclaw pairing list telegram
openclaw pairing approve telegram <CODE>

# Change the default model
ollama pull phi3:mini
openclaw config set agents.defaults.model.primary "ollama/phi3:mini"
```

## Logging

All installer output is logged to timestamped files:

```
~/glados-installer/logs/install_YYYYMMDD_HHMMSS.log
```

Logs are automatically stripped of ANSI colour codes for clean storage.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **"Another instance is already running"** | Remove the stale lock file: `rm /tmp/glados_installer.lock` |
| **Ollama API unreachable** | Check the service: `sudo systemctl status ollama` or `journalctl -u ollama` |
| **Model download fails** | Retry with `ollama pull <model>` — the installer supports automatic retries |
| **OpenClaw gateway not running** | Start it manually: `openclaw gateway start` |
| **Permission denied (Docker)** | Log out and back in after install, or run: `newgrp docker` |

## Project Structure

```
glados_installer/
├── glados_installer.sh   # Main installer script
├── README.md             # This file
├── LICENSE               # MIT License
├── CHANGELOG.md          # Version history
├── CONTRIBUTING.md        # Contribution guidelines
├── SECURITY.md           # Security policy
├── Makefile              # Development shortcuts
├── .editorconfig         # Editor consistency
├── .gitignore            # Git ignore rules
└── .github/
    ├── workflows/
    │   └── ci.yml        # ShellCheck CI pipeline
    └── ISSUE_TEMPLATE/
        ├── bug_report.md
        └── feature_request.md
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

For reporting vulnerabilities, please see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <sub>Built with ❤️ for the local AI community</sub>
</p>
