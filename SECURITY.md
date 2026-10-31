# Security Policy

## Supported versions

harness-mini is a small, pre-1.0 project. Only the **latest release** receives
security fixes — anything older is out of support.

| Version | Supported |
|---------|-----------|
| latest `v0.x` release | ✅ |
| older releases | ❌ — run `bin/harness.sh update` first, then re-check |

## Scope

**In scope**

- `init.sh` and `bin/*.sh` — the shell code that runs on developer machines. The
  installer and CLI are the security-sensitive surface: what they write, what
  they overwrite, and what they execute.
- Supply-chain integrity of a distributed install: the `harness/harness.lock`
  checksums and everything the `harness.sh update` path pulls in.
- Skills/agents content (`skills/`, `agents/`) that instructs a coding agent to
  perform unsafe actions on the host where harness-mini is installed.

**Out of scope**

- Vulnerabilities in the coding agents, models, editors, or hosts that
  harness-mini drives — report those to the upstream project.
- Vulnerabilities in *your* project after installing harness-mini (it grafts
  files in additively; your code remains your territory).
- Issues already fixed in a newer release.
- Social engineering, phishing, or denial-of-service against repository
  infrastructure.
- Anything only reachable by an attacker who already controls this repository
  or your local checkout.

## Reporting a vulnerability

**Please do not open a public issue or PR for a security problem.**

Use GitHub's private vulnerability reporting instead:
**[Report a vulnerability](https://github.com/harness-mini/harness-mini/security/advisories/new)**
(Security tab → "Report a vulnerability").

Please include:

- The affected file(s) and your installed version (`bin/harness.sh version`)
- A minimal reproduction — a shell transcript is ideal
- The impact you see, including how it crosses a trust boundary (developer
  machine, repo content, or CI)

## What to expect

- **Acknowledgment** within 7 days.
- **Assessment and a fix plan** (or a reasoned won't-fix) within 30 days for
  confirmed issues.
- **Coordinated disclosure:** we ask for up to 90 days before public disclosure.
  A fix ships as a tagged release plus a GitHub security advisory; you get
  credit in the advisory if you wish.

## Distributing a fix

Because installs are checksum-guarded, a security release flows the normal way:
a patched `vX.Y.Z` tag, then `bin/harness.sh update` on the installed side
(your local edits are preserved; see `ARCHITECTURE.md` → "Versioning & update
model").
