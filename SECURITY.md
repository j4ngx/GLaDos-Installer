# Security Policy

## Supported Versions

| Version | Supported          |
|---------|--------------------|
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

- **Secure downloads**: Scripts are downloaded to temporary files and validated (non-empty, shebang check) before execution
- **No credential logging**: Telegram bot tokens and sensitive data are never written to log files
- **Token memory cleanup**: Sensitive environment variables are `unset` after use
- **Hidden input**: Token prompts use `read -s` to prevent shoulder-surfing
- **Lock file protection**: Prevents concurrent execution that could cause race conditions
- **Strict mode**: `set -Eeuo pipefail` catches errors early
- **PATH validation**: Commands are verified on PATH before use
- **Version validation**: Minimum versions enforced for critical dependencies

## Best Practices for Users

- **Review the script** before running it, especially if downloaded via `curl | bash`
- **Use environment variables** for tokens instead of command-line arguments (which appear in process listings)
- **Run as a regular user** with `sudo` access, not as root
- **Keep components updated** after installation (`ollama update`, `apt upgrade`)
- **Bind to localhost** when using OpenClaw gateway for local-only access
