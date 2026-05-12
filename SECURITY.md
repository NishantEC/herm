# Security Policy

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security problems. Instead:

1. Open a private GitHub Security Advisory at https://github.com/NishantEC/herm/security/advisories/new
2. Include reproduction steps, affected versions, and the impact you observed.

I aim to acknowledge reports within 72 hours and to publish a fix or mitigation within 14 days for high-severity issues.

## Scope

In scope:
- Anything in the Terraform configuration that exposes resources beyond the documented controls in `docs/security.md`.
- Anything in `cloud-init/` or `systemd/` that escalates privilege or weakens the hardening described in the spec.
- `bin/herm` and `cli/` shell injection or secret-handling bugs.

Out of scope:
- Vulnerabilities in upstream dependencies (Hermes Agent, Tailscale, GCP). Report those to the respective project.
