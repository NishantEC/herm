# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-05-13

Consolidates the original v0.2/v0.3/v0.4 roadmap into a single release. **Multica deferred to v0.3** after live research found the brainstorm's HTTP-bearer agent-registration assumption doesn't match Multica's actual architecture (task board over WebSocket + subprocess CLI dispatch). Hermes Agent v0.13.0 natively provides the four properties the brainstorm wanted from Multica (tickets via sessions, heartbeats via `cronjob` toolset, skills in Anthropic Agent-Skills format, A2 invisible-subagents via `delegation`), so v0.2 ships Hermes-native and Multica returns in v0.3 after source-reading. **Cloud NAT also deferred** — the ~$32/mo cost was rejected by the owner; egress-allowlist paranoid mode follows later.

### Added

- **Skills system.** 6 initial skills under `skills/` in Anthropic Agent-Skills format (`SKILL.md` Markdown + YAML frontmatter): `debug`, `review-pr`, `write-doc`, `update-deps`, `watch-repo`, `summarize-day`. The latter two are cron-scheduled heartbeats; the rest are on-demand. Seeded into `~/.hermes/skills/herm/` on boot by `cloud-init/scripts/07-seed-skills.sh`; user-authored skills outside that namespace are preserved across `herm up`/`herm down` cycles.
- **Toolset disable policy.** `config/hermes-tools.yaml` declares which Hermes toolsets are turned off by default — `browser-cdp`, `computer_use`, external messaging (slack/discord/email/telegram/whatsapp/mattermost/matrix), `godmode`, `tts`, `voice`, `xurl`, niche toolsets. Applied to `agent.disabled_toolsets` in `~/.hermes/config.yaml` by `08-tool-allowlist.sh`.
- **Auto-reaper.** `systemd/herm-reaper.{service,timer}` halts the VM after `idle_hours` (default 168 = 7 days) of no owner-peer activity on the tailnet. Opt-in via `[reaper] enabled=true` in `~/.config/herm/config.toml`. Installed by `09-install-reaper.sh`.
- **9 new `herm` subcommands.** `login {claude|gh|gemini|codex|opencode|goose|all}`, `open {hermes|health|console|tailscale}`, `qr`, `rotate [hermes]`, `upgrade`, `backup [now|list]`, `restore <YYYY-MM-DD>`, `logs <unit>`, `console`. `herm help` regrouped into LIFECYCLE / DAY-TO-DAY / AUTH / MAINTENANCE.
- **`docs/skills.md`** and **`docs/rotation.md`** — full docs for the two new owner-facing primitives.
- **`docs/security.md`** updated with the toolset allowlist and reaper sections.
- **3 new bats tests** verify the renderer inlines skills, tool policy, and the reaper-enable flag (13/13 total pass).

### Fixed (during live integration on `flashckard`)

- **`tools.allowed/denied` key was theatrical.** The first draft of `config/hermes-tools.yaml` declared `allowed_tools:` and `denied_tools:` lists that Hermes ignores — Hermes' real disable mechanism is `agent.disabled_toolsets` (a flat list of toolset names). Both the policy file and the apply script switched to the real key. Caught when grep'ing the live VM's config and finding the stub `tools:` key Hermes parsed but never used.

### Deferred to v0.3

- **Multica orchestration.** Returns after reading `multica-ai/multica` source to find the actual runtime registration shape (the public docs at `/docs/agents/http` and `/docs/runtimes` both 404).
- **Cloud NAT + egress allowlist.** ~$32/mo gateway cost rejected.
- **Per-agent Podman sandboxing.** Significant implementation work; deferred until there's a second agent on the VM that needs isolation from Hermes.
- **CMEK.** Optional `herm up --cmek` flag stubbed in spec but not implemented — limited blast radius reduction relative to the implementation cost.
- **`herm upgrade` disk-snapshot auto-rollback.** The snapshot step works; the auto-rollback on health-check failure is the deferred half.
- **Native desktop / mobile client.** Hermes Desktop / AionUI wiring is still manual on the laptop side.

[Unreleased]: https://github.com/NishantEC/herm/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/NishantEC/herm/releases/tag/v0.2.0

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

[0.1.0]: https://github.com/NishantEC/herm/releases/tag/v0.1.0
