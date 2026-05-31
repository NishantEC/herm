# Security Controls — herm v0.1

This document lists every defensive control v0.1 ships with. Pair it with `docs/threat-model.md` for what's *not* covered.

## Network

- VM has an **ephemeral external IPv4** for outbound egress (apt, npm, Tailscale package fetches). This is a v0.1 relaxation of the original "no external IP" stance: the deny-all-ingress firewall below makes the public IP carry zero attack surface (connections can be initiated outbound only), and a v0.1 Cloud NAT would add ~$32/mo. v0.4 paranoid mode reverts to no external IP + Cloud NAT + egress allowlist. See `terraform/vm.tf` for rationale.
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

## Toolset allowlist (v0.2)

Hermes Agent v0.13.0 ships with 22+ toolsets. v0.2 disables the ones we don't need in the default deployment by writing to `agent.disabled_toolsets` in `/home/herm/.hermes/config.yaml`. The policy lives in `config/hermes-tools.yaml` in the repo and is applied by `cloud-init/scripts/08-tool-allowlist.sh` on first boot.

Disabled by default:
- `browser-cdp` — full Chrome DevTools Protocol; way more surface than the in-process `browser` toolset.
- `computer_use` — mouse/keyboard control on the host. Extreme blast radius on a VM that holds your `gh` token.
- `discord`, `email`, `telegram`, `whatsapp`, `mattermost`, `matrix` — external messaging connectors. Not wired by default; enabling them connects your agent to chat platforms whose creds need their own threat model.
- `godmode` — Hermes' built-in red-teaming skill. Explicit opt-in only.
- `tts`, `voice` — cost without functional value in v0.2.
- `xurl` — generic HTTP fetch. Bypasses the per-tool allowlists below it.
- `minecraft-modpack-server`, `pokemon-player` — niche.

`slack` is the one external-messaging connector left **enabled** (Hermes' Socket Mode adapter) — it's the supported owner↔agent channel. It stays dormant until you set `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` in `~/.hermes/.env`. Treat those as credentials with real blast radius: Hermes defaults to **deny-all**, so without `SLACK_ALLOWED_USERS` every inbound DM is dropped, and anyone you add to that allowlist can drive the agent. See [`docs/integrations/slack.md`](integrations/slack.md).

To re-enable any of these, remove the entry from `config/hermes-tools.yaml` and run `herm upgrade`. Or edit `~/.hermes/config.yaml` directly on the VM and `pkill -9 -f 'hermes gateway'`.

## Auto-reaper (v0.2, opt-in)

`systemd/herm-reaper.{service,timer}` halts the VM after 7 days (default) of no tailnet activity from owner-tagged peers. Disabled by default; enable per `~/.config/herm/config.toml`:

```toml
[reaper]
enabled = true
idle_hours = 168
```

Then `herm upgrade` to apply.

When the reaper fires the VM is halted (not deleted) — the persistent disk and Secret Manager entries survive. `gcloud compute instances start herm-vm` brings it back.

## Token rotation (v0.2)

`herm rotate` regenerates the Hermes API server bearer token; see [`docs/rotation.md`](rotation.md). Recommended quarterly or after any time the token has been pasted into a chat/log.

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
