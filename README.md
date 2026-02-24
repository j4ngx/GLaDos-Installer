<p align="center">
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white" alt="Shell: Bash">
  <img src="https://img.shields.io/badge/platform-Debian%2013-A81D33?logo=debian&logoColor=white" alt="Platform: Debian 13">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/version-3.0.0-brightgreen" alt="Version: 3.0.0">
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
  Ollama · OpenClaw · Whisper STT · Piper TTS · SearXNG · Telegram
  <br>
  Static IP · Swap · GPU · Firewall · Hardening · Health Monitoring · Backup/Restore
</p>

---

## Overview

GLaDOS Installer is a professional, modular installer that sets up a complete **local AI assistant environment** on Debian-based systems. It is specifically optimised for low-power hardware like the Intel N4000 with 8 GB RAM, but works on any compatible x86_64 or ARM64 machine.

The installer orchestrates **17 library modules** across 4 installation phases — from system foundations (networking, swap, GPU) through core services (Ollama, OpenClaw) to optional features (voice, web search, Telegram) and server hardening (firewall, SSH, health monitoring).

**What gets installed:**

| Component | Description |
|-----------|-------------|
| **[Ollama](https://ollama.com)** | Local LLM runtime for running models on-device |
| **Meta Llama 3** | Default language model (configurable) |
| **[OpenClaw](https://openclaw.ai)** | Personal AI assistant with gateway and CLI |
| **[whisper.cpp](https://github.com/ggerganov/whisper.cpp)** | Offline speech-to-text (STT) via GGML models |
| **[Piper TTS](https://github.com/rhasspy/piper)** | Offline text-to-speech (TTS) with multi-voice support |
| **[SearXNG](https://github.com/searxng/searxng)** | Self-hosted meta-search engine for real-time web access |
| **Static IP** | Automatic network configuration (nmcli / ifupdown / netplan) |
| **Swap management** | Auto-sized swap file optimised for LLM workloads |
| **GPU acceleration** | NVIDIA (Container Toolkit) and AMD (ROCm) auto-detection |
| **UFW firewall** | Deny-by-default firewall with SSH rate limiting |
| **System hardening** | SSH hardening, unattended security updates, log rotation |
| **Health monitoring** | Cron-based health checks with Telegram/syslog alerts |
| **Backup/Restore** | Full configuration backup, restore, and uninstall tools |
| **Telegram Bot** | Optional Telegram integration for remote access |

## Features

- ✨ **Single command** — fully automated installation from scratch
- 🧩 **Modular architecture** — 17 independent library modules in `lib/`
- 🔒 **Secure downloads** — validates scripts before execution
- 🔄 **Idempotent** — safe to re-run; skips already-installed components
- 🎯 **Pre-flight checks** — validates RAM, disk, CPU, audio hardware, network before starting
- 🎨 **Beautiful CLI** — coloured output, spinners, progress tracking
- 🛡️ **Robust error handling** — `set -Eeuo pipefail`, trap handlers, lock files
- 📝 **Full logging** — timestamped logs saved to `~/glados-installer/logs/`
- ⚙️ **Highly configurable** — 30+ CLI flags for fine-grained control
- 🤖 **Non-interactive mode** — unattended installs for automation
- 📊 **Status command** — check health of all components at a glance
- 🌐 **Proxy support** — HTTP/HTTPS proxy passthrough for corporate networks
- 🔧 **Maintenance tools** — backup, restore, and uninstall commands
- 🖥️ **GPU auto-detection** — NVIDIA and AMD acceleration with Docker passthrough
- 🔥 **Server hardening** — UFW firewall, SSH lockdown, unattended security upgrades

## Requirements

| Requirement | Minimum |
|-------------|---------|
| **OS** | Debian 13 (other Debian-based distros may work) |
| **Architecture** | x86_64 or ARM64 |
| **RAM** | 4 GB (8 GB recommended) |
| **Disk** | 15 GB free space |
| **Network** | Internet access required for downloads |
| **Privileges** | `sudo` access |

### Dependencies (auto-installed)

`curl`, `wget`, `git`, `ca-certificates`, `gnupg`, `lsb-release`, `build-essential`, `cmake`, `libopenblas-dev`, `jq`, `Docker`, `alsa-utils`, `sox`, `python3`, `ffmpeg`, `ufw`

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
GLaDOS Installer v3.0.0

USAGE
  glados_installer.sh [OPTIONS]

CORE OPTIONS
  --model <tag>           Ollama model tag        (default: llama3)
                          Examples: llama3, llama3.1:instruct, phi3:mini
  --agent-name <name>     OpenClaw agent label    (default: GLaDOS)
  --whisper-model <size>  Whisper STT model size  (default: small)
                          Values: tiny · base · small · medium · large · large-v2 · large-v3
  --piper-voice <name>    Piper TTS voice name    (default: en_US-lessac-medium)
  --static-ip <ip>        Set a static IP         (e.g. 192.168.1.100)
  --static-gw <ip>        Static IP gateway       (e.g. 192.168.1.1)
  --static-dns <ip>       Static IP DNS server    (default: 1.1.1.1)
  --static-mask <cidr>    Static IP netmask CIDR  (default: 24)

SERVER TUNING
  --swap-size <MB>        Swap file size in MB    (default: auto — match RAM, cap 8 GB)
  --ssh-port <port>       SSH port for firewall   (default: 22)
  --hostname <name>       Set system hostname     (empty = prompt interactively)
  --timezone <tz>         Set timezone            (e.g. Europe/Madrid, default: auto-detect)
  --http-proxy <url>      HTTP proxy URL          (e.g. http://proxy:3128)
  --https-proxy <url>     HTTPS proxy URL

FEATURE FLAGS
  --skip-static-ip        Skip static IP configuration prompt
  --skip-swap             Skip swap file creation
  --skip-gpu              Skip GPU detection and acceleration setup
  --skip-firewall         Skip UFW firewall configuration
  --skip-hardening        Skip system hardening (hostname, SSH, upgrades)
  --skip-healthcheck      Skip cron health monitoring setup
  --skip-audio            Do not install voice input/output (Whisper + Piper)
  --skip-internet         Do not deploy SearXNG web-search
  --skip-telegram         Skip Telegram channel configuration
  --skip-onboard          Skip 'openclaw onboard' wizard (run manually later)

RUN-MODE FLAGS
  --non-interactive       Accept all defaults without prompting
  --dry-run               Show what would be done without making changes
  --verbose               Enable debug-level output
  --status                Show current installation status and exit
  --help, -h              Show this message and exit

MAINTENANCE
  --backup                Create a backup of GLaDOS configuration
  --restore [file]        Restore from a backup archive
  --uninstall             Remove all GLaDOS components

ENVIRONMENT VARIABLES
  TELEGRAM_BOT_TOKEN      Telegram bot token (export before running)
  HTTP_PROXY              HTTP proxy (alternative to --http-proxy)
  HTTPS_PROXY             HTTPS proxy (alternative to --https-proxy)
```

### Examples

```bash
# Full install with all defaults (recommended)
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

# Tiny Whisper model with custom TTS voice
./glados_installer.sh --whisper-model tiny --piper-voice en_US-lessac-high

# Pre-set a static IP (non-interactive)
./glados_installer.sh --static-ip 192.168.1.100 --static-gw 192.168.1.1

# Server hardening with custom hostname and timezone
./glados_installer.sh --hostname glados-server --timezone Europe/Madrid

# Minimal install: skip heavy optional features
./glados_installer.sh --skip-audio --skip-internet --skip-telegram --skip-gpu

# Behind a corporate proxy
./glados_installer.sh --http-proxy http://proxy:3128 --https-proxy http://proxy:3128

# Backup current state
./glados_installer.sh --backup

# Restore from backup
./glados_installer.sh --restore

# Uninstall everything
./glados_installer.sh --uninstall
```

## Installation Steps

The installer executes the following steps across 4 phases:

```
Phase 1 — System Foundations
  [ 1/17]  Pre-flight system checks
  [ 2/17]  Static IP configuration            (skippable)
  [ 3/17]  Swap file management                (skippable)
  [ 4/17]  GPU detection & acceleration        (skippable)

Phase 2 — Core Packages & Services
  [ 5/17]  Installing base system packages
  [ 6/17]  Docker runtime
  [ 7/17]  Ollama installation
  [ 8/17]  Pulling Ollama model
  [ 9/17]  OpenClaw installation
  [10/17]  OpenClaw onboarding wizard          (skippable)
  [11/17]  Configuring OpenClaw ↔ Ollama

Phase 3 — Optional Features
  [12/17]  Voice interface (Whisper + Piper)    (skippable)
  [13/17]  Internet / web-search (SearXNG)     (skippable)
  [14/17]  Telegram channel configuration      (skippable)

Phase 4 — Server Hardening & Monitoring
  [15/17]  UFW firewall                        (skippable)
  [16/17]  System hardening (SSH, upgrades)    (skippable)
  [17/17]  Cron health monitoring              (skippable)
```

Step count is **dynamically calculated** based on which `--skip-*` flags are active. Each step includes health checks and graceful error recovery.

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

# Voice chat (if audio installed)
glados-voice                          # interactive voice loop
glados-stt 5                          # record 5 seconds → text
echo "Hello world" | glados-tts       # text → speech

# Web search (if SearXNG installed)
curl -s 'http://127.0.0.1:8888/search?q=latest+news&format=json' | jq '.results[0].title'

# Telegram pairing (if configured)
openclaw channels status
openclaw pairing list telegram
openclaw pairing approve telegram <CODE>

# Maintenance commands
./glados_installer.sh --status        # health overview
./glados_installer.sh --backup        # backup all config
./glados_installer.sh --restore       # restore from backup
./glados_installer.sh --uninstall     # remove everything

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
| **SearXNG container won't start** | Check Docker logs: `docker compose -f ~/glados-installer/searxng/docker-compose.yml logs` |
| **Voice recording fails** | Verify audio hardware: `arecord -l` and check `alsa-utils` is installed |
| **GPU not detected** | Verify drivers: `nvidia-smi` (NVIDIA) or `rocm-smi` (AMD) |
| **UFW blocking connections** | Check rules: `sudo ufw status verbose` |
| **SSH lockout after hardening** | If password auth was disabled, ensure SSH keys are set up beforehand |
| **Health check cron not running** | Verify: `crontab -l \| grep glados-healthcheck` |
| **Static IP not applied** | Check backend: `nmcli` / `ip addr` / `cat /etc/network/interfaces` |

## Project Structure

```
glados_installer/
├── glados_installer.sh   # Main installer script (entry point)
├── lib/
│   ├── common.sh         # Shared constants, logging, utilities
│   ├── preflight.sh      # Pre-flight system checks
│   ├── network.sh        # Static IP configuration (nmcli/ifupdown/netplan)
│   ├── swap.sh           # Swap file management (auto-sized for LLM)
│   ├── gpu.sh            # GPU detection & acceleration (NVIDIA/AMD)
│   ├── packages.sh       # APT base package installation
│   ├── docker.sh         # Docker runtime setup
│   ├── ollama.sh         # Ollama install & model management
│   ├── openclaw.sh       # OpenClaw CLI, onboarding & config
│   ├── audio.sh          # whisper.cpp STT + Piper TTS + wrappers
│   ├── internet.sh       # SearXNG web-search via Docker Compose
│   ├── telegram.sh       # Telegram bot channel configuration
│   ├── firewall.sh       # UFW firewall with SSH rate limiting
│   ├── hardening.sh      # SSH hardening, unattended upgrades, logrotate
│   ├── healthcheck.sh    # Cron-based health monitoring & alerting
│   └── backup.sh         # Backup, restore, and uninstall utilities
├── README.md             # This file
├── LICENSE               # MIT License
├── CHANGELOG.md          # Version history
├── CONTRIBUTING.md       # Contribution guidelines
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

## Module Details

### Static IP (`lib/network.sh`)

Configures a static IP address on the primary network interface. Auto-detects the active interface via default route and supports three backends:

- **NetworkManager** (`nmcli`) — preferred on modern Debian
- **ifupdown** (`/etc/network/interfaces`) — legacy Debian
- **netplan** — Ubuntu-based systems

Original configuration is backed up before changes. Post-apply verification ensures connectivity.

### Swap Management (`lib/swap.sh`)

Creates and activates a swap file optimised for LLM workloads:

- **Auto-sizing**: matches RAM size, minimum 2 GB, maximum 8 GB
- **Filesystem aware**: uses `dd` on btrfs/zfs, `fallocate` otherwise
- **Persistent**: added to `/etc/fstab`
- **Tuned**: sets `vm.swappiness=10` via `/etc/sysctl.d/99-glados.conf`

### GPU Acceleration (`lib/gpu.sh`)

Auto-detects NVIDIA and AMD GPUs and configures acceleration:

- **NVIDIA**: checks `nvidia-smi`, offers driver installation, installs NVIDIA Container Toolkit for Docker GPU passthrough, restarts Ollama
- **AMD**: checks ROCm, adds user to `render`/`video` groups
- **Intel/CPU-only**: graceful fallback with no extra packages

### UFW Firewall (`lib/firewall.sh`)

Configures a deny-by-default firewall:

- Denies all incoming, allows all outgoing
- Allows SSH (configurable port via `--ssh-port`)
- Rate-limits SSH to prevent brute-force attacks
- Allows loopback traffic
- Idempotent: skips if already active

### System Hardening (`lib/hardening.sh`)

Applies security best practices:

- **Hostname**: RFC 1123 validated, updates `/etc/hosts`
- **Timezone**: validated against `timedatectl`, enables NTP sync
- **SSH hardening** (drop-in config at `/etc/ssh/sshd_config.d/50-glados-hardening.conf`):
  - Disables root login and password auth (keeps password auth if no SSH keys found)
  - Max 3 auth tries, disables X11/agent forwarding
  - Tests config before applying, backs up original
- **Unattended upgrades**: security-only, auto-clean every 7 days
- **Log rotation**: weekly rotation of installer logs (4 retained, compressed)

### Health Monitoring (`lib/healthcheck.sh`)

Installs a cron-based monitoring system:

- Writes standalone `glados-healthcheck` script to `~/.local/bin/`
- Checks: Ollama API, OpenClaw gateway, SearXNG container, Docker daemon
- Logs to `~/glados-installer/logs/healthcheck.log`
- Alerts via `openclaw notify` (Telegram) or `logger` (syslog) fallback
- Runs every 5 minutes via cron

### Backup & Restore (`lib/backup.sh`)

Full configuration management:

- **Backup** (`--backup`): exports OpenClaw config, Ollama model list, SearXNG settings, network config, SSH hardening, UFW rules, Piper voices, crontab, and system info into a timestamped `tar.gz` in `~/glados-installer/backups/`
- **Restore** (`--restore [file]`): lists available backups with numbered selection, extracts and imports configs
- **Uninstall** (`--uninstall`): removes OpenClaw, SearXNG containers + data, whisper.cpp, Piper TTS, wrapper scripts, healthcheck cron. Preserves Ollama, Docker, APT packages, and SSH hardening. Offers backup before proceeding.

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
