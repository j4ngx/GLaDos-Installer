# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
| 3.x.x  | ✅ Yes             |
| 2.x.x  | ✅ Yes             |
| < 2.0   | ❌ No              |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, **please do not open a public issue**.

Instead, report it privately:

1. **Email**: Send details to the repository maintainer via GitHub's private messaging
2. **GitHub Security Advisory**: Use the [Security tab](https://github.com/j4ngx/glados_installer/security/advisories) to create a private advisory

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgement**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Fix release**: Depends on severity (critical: ASAP, others: next release)

## Security Measures in This Project

The installer implements several security practices:

### Download & Execution Safety
- **Secure downloads**: Scripts are downloaded to temporary files and validated (non-empty, shebang check) before execution
- **Docker validation**: Docker convenience script verified before running with `sudo`
- **Strict mode**: `set -Eeuo pipefail` catches errors early
- **Lock file protection**: Prevents concurrent execution that could cause race conditions

### Credential Management
- **No credential logging**: Telegram bot tokens and sensitive data are never written to log files
- **Token memory cleanup**: Sensitive environment variables are `unset` after use
- **Hidden input**: Token prompts use `read -s` to prevent shoulder-surfing
- **Process-safe tokens**: Telegram bot token passed via environment, never as CLI arg (invisible in `ps`)

### Network Security
- **UFW firewall**: Deny-by-default policy configured automatically
- **SSH rate limiting**: Brute-force protection via UFW rate limits on SSH port
- **Localhost binding**: SearXNG and OpenClaw gateway bound to `127.0.0.1` only
- **Docker container hardening**: SearXNG runs with `cap_drop: ALL` and minimal `cap_add`

### System Hardening
- **SSH hardening**: Drop-in config disables root login, password auth (when SSH keys exist), X11/agent forwarding
- **Unattended upgrades**: Security-only patches applied automatically
- **Config backup**: Original SSH, network, and system configs backed up before modification
- **SSH config testing**: `sshd -t` validates config before applying changes

### File Permissions
- **SearXNG settings**: `chmod 600` (contains secret key)
- **Swap file**: `chmod 600` (restricted permissions)
- **SSH drop-in config**: Standard restrictive permissions

### Monitoring
- **Health monitoring**: Cron-based checks every 5 minutes for all services
- **Alert integration**: Failures reported via `openclaw notify` (Telegram) or `logger` (syslog)
- **Log rotation**: Automatic weekly rotation prevents disk exhaustion

### Validation
- **PATH validation**: Commands are verified on PATH before use
- **Version validation**: Minimum versions enforced for critical dependencies (curl, git, Docker)
- **IPv4 validation**: Static IP input validated, rejects leading zeros and ambiguous octals
- **Hostname validation**: RFC 1123 compliance enforced
- **Timezone validation**: Checked against `timedatectl list-timezones`

## Best Practices for Users

- **Review the script** before running it, especially if downloaded via `curl | bash`
- **Use environment variables** for tokens instead of command-line arguments (which appear in process listings)
- **Run as a regular user** with `sudo` access, not as root
- **Keep components updated** after installation (`ollama update`, `apt upgrade`)
- **Bind to localhost** when using OpenClaw gateway for local-only access
- **Set up SSH keys** before running the installer — the hardening module will disable password auth if keys are found
- **Review firewall rules** after installation: `sudo ufw status verbose`
- **Create a backup** before making changes: `./glados_installer.sh --backup`
- **Monitor health logs** at `~/glados-installer/logs/healthcheck.log`
- **Do not expose SearXNG** to the internet — it is bound to localhost by design
