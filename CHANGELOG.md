# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-13

First end-to-end working release: provisions a private GCP VM running Hermes Agent v0.13.0, joins it to your tailnet, persists state across rebuilds, and serves the gateway API on port 8642. Validated end-to-end against `flashckard` with `claude-sonnet-4-6` via Anthropic OAuth.

### Added

- Initial design spec (`docs/superpowers/specs/2026-05-13-herm-design.md`).
- v0.1 implementation plan (`docs/superpowers/plans/2026-05-13-herm-v0.1.md`).
- Terraform-provisioned GCP infrastructure: VPC with default-deny ingress, IAP-SSH break-glass firewall, `e2-small` VM (Shielded VM, OS Login, ephemeral STANDARD-tier external IPv4 for outbound egress), 10GB PD-SSD with `prevent_destroy`, GCS backup bucket with object versioning, dedicated scoped-IAM service account, Secret Manager for the one-shot Tailscale auth key.
- GCE startup-script that mounts the persistent disk, creates the unprivileged `herm` user, installs Tailscale, installs Hermes Agent via the official `install.sh`, generates an API server bearer token, joins the tailnet using the secret-managed auth key (then deletes the secret), and enables a hardened `hermes-agent.service` + nightly `herm-backup.timer`.
- `herm` CLI: `init`, `up`, `up --replace-vm`, `down`, `nuke`, `status`, `ssh`.
- CI workflows: `shellcheck --severity=warning`, `terraform fmt/validate`, `tflint`, `trivy config`, `gitleaks`, `markdownlint`.
- bats unit tests for `cli/lib.sh` helpers and the startup-script renderer.
- Threat model, security controls, cost breakdown, troubleshooting docs.

### Fixed during the v0.1 integration run

These all surfaced during ten hours of live integration against a real GCP project. Each commit on `main` between the initial spec and the `v0.1.0` tag fixes a real bug that didn't show up until the actual VM tried to boot:

- **`herm up` ADC missing**: `herm init` now runs `gcloud auth application-default login` when `~/.config/gcloud/application_default_credentials.json` is absent; `herm up` fails fast with a clear message instead of letting Terraform error opaquely with `credentials: could not find default credentials`.
- **GCS self-referential logging block**: `terraform/storage.tf` no longer declares a bucket-level `logging` sink (GCS forbids a bucket logging to itself; a separate log bucket is a v0.4 task).
- **`debian-cloud/debian-12` doesn't run cloud-init**: rewrote the VM bootstrap from a cloud-init YAML (silently no-op'd) to a GCE-native `startup-script` that google-startup-scripts.service actually executes.
- **`tflint` unused-variable warnings**: removed `tailnet_owner_tag` and `budget_monthly_usd` Terraform variables (both managed outside Terraform — Tailscale admin console + `gcloud billing budgets` respectively).
- **`apt-get install` IPv6 routing**: the default GCE VPC has no IPv6 egress but `deb.debian.org` resolves to AAAA records first; added `/etc/apt/apt.conf.d/99-herm-force-ipv4` to pin apt to IPv4.
- **No public-internet egress for the VM**: the original "no external IP" stance combined with no Cloud NAT made `apt-get install` fail with `Network is unreachable` for any non-Google host. v0.1 attaches an ephemeral STANDARD-tier external IPv4 (free); the deny-all-ingress firewall ensures the IP carries zero inbound attack surface. v0.4 paranoid mode reverts to no external IP + Cloud NAT + egress allowlist.
- **Made-up npm package name for Hermes Agent**: replaced `npm install -g hermes-agent@1.4.0` (fictitious) with the real upstream install method: `curl ... install.sh | bash` from `NousResearch/hermes-agent` running as the `herm` user, dropping a symlink at `~/.local/bin/hermes`.
- **Wrong server CLI command**: `systemd/hermes-agent.service` `ExecStart` is `~/.local/bin/hermes gateway` (the real command), not `hermes-agent serve` (which I made up).
- **`~/.hermes/.env` schema**: `API_SERVER_ENABLED=true` + `API_SERVER_KEY=<token>` are the actual env vars Hermes reads, replacing the invented `HERMES_API_TOKEN_FILE`.
- **Tailscale `--advertise-tags=tag:herm-vm`**: dropped — tags must be pre-declared in the tailnet ACL before a node can advertise them, and the example ACL in `examples/tailscale-acl.hujson.example` is documentation only. v0.1 joins as a regular personal node under the owner's identity.
- **Anthropic SDK missing from Hermes' venv**: the upstream installer doesn't bundle the `anthropic` extra. `04-install-hermes.sh` now runs `uv pip install --python ~/.hermes/hermes-agent/venv/bin/python 'anthropic>=0.39.0'` so `/v1/chat/completions` works against the Anthropic provider out of the box.
- **`.api-token` empty-file regen**: switched from `[[ ! -f ]]` to `[[ ! -s ]]` so we regenerate any zero-byte token file left behind by a partially-failed prior bootstrap on the same persistent disk.
- **`up.sh` unbound-variable on exit**: cleaned up the `local tmp` + `trap EXIT` interaction that printed `tmp: unbound variable` after every apply.
- **OS Login for sudo**: documented that `tailscale ssh herm@herm-vm` lands as the unprivileged `herm` user (no password by design); maintenance that needs sudo goes through `gcloud compute ssh --tunnel-through-iap` which uses Google identity + OS Login.

### Known limitations

- **Auxiliary LLM provider unconfigured**: Hermes warns "No auxiliary LLM provider configured" because it wants a separate (typically cheaper) model for title generation and middle-turn summarization. Primary chat works. Wire up `OPENROUTER_API_KEY` in `~/.hermes/.env` to silence it; deferred to v0.2.
- **No `herm login`, `herm open`, `herm qr`, `herm rotate`, `herm upgrade`, `herm backup/restore`, `herm logs`** — all v0.3.
- **No Multica orchestration / skills system / heartbeats / tickets** — that's the whole point of v0.2.
- **No paranoid mode** (`herm up --paranoid`): no Cloud NAT + egress allowlist, no CMEK, no per-agent Podman sandboxing, no tool allowlist enforcement, no auto-reaper — all v0.4.
- **`herm nuke` friction**: the PD-SSD has `prevent_destroy=true`, so `herm nuke` instructs you to comment out the lifecycle block in `terraform/disk.tf` and rerun. A `--force` flag that toggles the lifecycle automatically is v0.2.
- **Auth handling on the VM is intentionally manual**: the `herm` user has no sudo (by design); paste the Tailscale auth key into `herm up` interactively each time.

[Unreleased]: https://github.com/NishantEC/herm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/NishantEC/herm/releases/tag/v0.1.0
