# Security Controls — herm v0.1

This document lists every defensive control v0.1 ships with. Pair it with `docs/threat-model.md` for what's *not* covered.

## Network

- VM has no external IP (`access_config` block omitted in `terraform/vm.tf`).
- VPC firewall: default-deny ingress. No `allow` rules on tcp.
- Egress: unrestricted in v0.1 (Cloud NAT egress allowlist is a v0.4 feature).
- Reachability: only via Tailscale. Tailscale ACL template at `examples/tailscale-acl.hujson.example` limits node access to the owner's tagged devices.

## Identity & access

- VM uses a dedicated service account `herm-vm@<project>.iam.gserviceaccount.com`.
- IAM bindings (see `terraform/iam.tf`):
  - `roles/secretmanager.secretAccessor` on the Tailscale auth-key secret only.
  - `roles/storage.objectAdmin` on the backup bucket only.
- No project-level roles. No `compute.instanceAdmin`. No `iam.serviceAccountUser`.
- OS Login is enabled on the VM. SSH access is gated by Google IAM, not by SSH keys in `~/.ssh/`.

## Secrets

- Secret Manager holds the Tailscale ephemeral auth key (single-use, `ephemeral=true`). Cloud-init deletes the secret entry after a successful tailnet join.
- Hermes Agent's API server token is generated on first boot and stored at `/home/herm/.hermes/.api-token` with mode `0600`, owned by `herm`. Not stored in Secret Manager in v0.1 (v0.4 will store + rotate).

## Data at rest

- Persistent disk: GCE encryption at rest (Google-managed key).
- GCS backup bucket: uniform bucket-level access, object versioning enabled, `storage.objectAdmin` only for the VM service account.
- `/home/herm` is owned by the `herm` user with mode `0700`.

## Runtime hardening

The Hermes Agent systemd unit ships with:

- `User=herm` / `Group=herm` — no root
- `NoNewPrivileges=true`
- `ProtectSystem=strict`
- `ProtectHome=read-only` (with `/home/herm` whitelisted via `ReadWritePaths`)
- `PrivateTmp=true`
- `CapabilityBoundingSet=` (empty)
- `RestrictSUIDSGID=true`
- `LockPersonality=true`
- `MemoryDenyWriteExecute=true`
- `SystemCallFilter=@system-service` `~@privileged @mount`
- `WatchdogSec=1800` — 30-minute wall-clock watchdog

## Cost runaway

- VM machine type locked to `e2-small` in `terraform/variables.tf` (overridable by the owner, but the default is the documented cost ceiling).
- GCP Budget alert created by `herm init` at $25/mo, 50/80/100% email pings.
- `herm down` shuts the VM off completely; the only idle cost is PD-SSD + GCS storage.

## Supply chain

- Every installed package pinned to an exact version in `cloud-init/scripts/`:
  - `node` — pinned major.minor.patch
  - `tailscale` — pinned
  - `hermes-agent` — pinned
- Dependabot configured to PR version bumps for review.

## Auditability

- VM stdout/journald → Cloud Logging (default project sink), 30-day retention.
- GCS Data Access events captured by project-level Cloud Audit Logs (default in GCP). A bucket-level access-log sink to a separate log bucket is a v0.4 task — see `docs/superpowers/specs/2026-05-13-herm-design.md`.

## Blast radius

- `herm down` deletes the VM and the ephemeral firewall/secrets entries. Persistent disk + GCS bucket survive.
- `herm nuke` (double-confirms) destroys everything including the persistent disk.
