# Threat Model — herm v0.1

This document is the honest answer to "what risk am I taking by running herm?"

## What you're trusting

By running `herm up` against your GCP project, you trust:

- **Google Cloud Platform** with your VM, persistent disk, secrets, and audit logs.
- **Tailscale** with the network identity that connects your devices to the VM.
- **NousResearch / Hermes Agent maintainers** with the autonomous agent code that runs on your VM.
- **The maintainers of the apt, npm, and GitHub packages** pinned in `cloud-init/scripts/`.
- **This repository** — every commit on `main`. Read the diff before `herm upgrade`.

## What you're protecting against (v0.1)

| Threat | Control |
|---|---|
| Random internet attacker reaching the VM | No external IP; VPC firewall denies ingress; Tailscale only |
| Stolen Tailscale auth key | Auth key is single-use, ephemeral, deleted from Secret Manager after first boot |
| Compromised SSH key on your laptop | OS Login: SSH is gated by Google IAM + 2FA, not local SSH keys |
| Service account credential theft | Service account has only `secretAccessor` (scoped) and `storage.objectAdmin` on one bucket. No project-level roles. |
| Runaway agent loop costing money | Per-turn wall-clock watchdog (30 min SIGTERM); GCP budget alert at $25/mo |
| Agent process escalating to root | Runs as unprivileged `herm` user; systemd `NoNewPrivileges=true`, `ProtectSystem=strict`, empty `CapabilityBoundingSet` |
| Disk failure | Nightly rsync to GCS bucket with object versioning |

## What v0.1 does NOT protect against

- **Prompt-injection-driven exfiltration to attacker hosts.** v0.1 allows arbitrary egress. v0.4 (`--paranoid`) adds a Cloud NAT egress allowlist.
- **A compromised Hermes Agent CLI release on npm.** Pinning + Dependabot is mitigation, not prevention.
- **A compromised upstream apt package.** Same.
- **A malicious PR merged to `main`.** CODEOWNERS reduces likelihood, doesn't eliminate.
- **Cross-agent token theft.** v0.1 has one agent (Hermes); v0.4 adds per-agent Podman sandboxing when more agents land.

If any of these are blocking concerns for you, wait for v0.4 or fork and harden.
