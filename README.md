# herm

> Headless AI agent workstation on Google Cloud, reachable from all your devices over Tailscale.

[![CI](https://github.com/NishantEC/herm/actions/workflows/ci.yml/badge.svg)](https://github.com/NishantEC/herm/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

`herm` provisions a small, private GCP VM running [Hermes Agent](https://github.com/nousresearch/hermes-agent), joins it to your Tailscale tailnet, and gives you an always-on, OpenAI-compatible AI agent — with skills, tool integrations, and an optional Slack bot — reachable from your laptop, phone, or any tailnet device, with **no inbound ports open to the public internet**. A single CLI (`herm`) provisions, manages, backs up, and tears the whole thing down.

> ⚠️ **v0.2.0 — early but working.** Validated end-to-end on a real GCP project; expect rough edges. See the [changelog](CHANGELOG.md).

## What you get

- **A private agent VM** — GCP `e2-small` (Debian 12, Shielded VM) running Hermes Agent v0.13.0, serving an OpenAI-compatible gateway at `:8642`.
- **Tailnet-only access** — reach it from any device on your Tailscale tailnet; the VPC firewall denies *all* public ingress.
- **Skills + a package manager** — 6 built-in skills (`debug`, `review-pr`, `write-doc`, `update-deps`, `watch-repo`, `summarize-day`), installed/enabled/disabled from your laptop with `herm skills` — no root, no reprovision.
- **A CLI fleet** — `claude`, `gh`, `gemini`, `codex`, `opencode` installed for the agent and for you.
- **MCP integrations** — Asana, Linear, and Figma (PAT-based, opt-in).
- **A Slack bot** — optional, over Socket Mode, deny-all by default.
- **Hardened by default** — 14 risky Hermes toolsets (Chrome DevTools, computer-use, most external messaging, …) disabled out of the box.
- **Durable and cheap** — state lives on a persistent disk that survives rebuilds, with nightly GCS backups, for **~$13/month at idle**.
- **One CLI for everything** — `herm up`, `down`, `ssh`, `logs`, `backup`, `upgrade`, … (full table [below](#commands)).

## How it works

```text
  your devices  (laptop · phone · CI)
       │
       │  Tailscale tailnet (WireGuard) — no public ingress
       ▼
  herm-vm · GCP e2-small · Debian 12 (Shielded VM)
  VPC firewall: deny-all from 0.0.0.0/0
       │
       ├─ Hermes Agent ──► OpenAI-compatible gateway  :8642
       │    ├─ skills          managed by `herm skills` (skillpm)
       │    ├─ MCP servers     asana · linear · figma
       │    ├─ Slack adapter   Socket Mode (opt-in)
       │    └─ CLI fleet       claude · gh · gemini · codex · opencode
       │
       ├─ persistent PD-SSD    state survives rebuilds
       └─ nightly backup ────► GCS bucket
```

Infrastructure is [Terraform](terraform/); first-boot setup is a rendered GCE startup script ([`cloud-init/scripts/`](cloud-init/scripts/)). The `herm` CLI ([`bin/herm`](bin/herm) + [`cli/`](cli/)) wraps Terraform locally and manages the VM over Tailscale SSH.

## Cost

`herm` runs a real GCP VM. Expect **~$13/month at idle**, plus your LLM API costs. Set a [GCP budget alert](https://cloud.google.com/billing/docs/how-to/budgets) before running this — `herm` configures one at $25/mo by default, but pick your own ceiling. An opt-in auto-reaper can halt the VM after a configurable idle period to cut cost further.

## Security

`herm` installs an autonomous AI agent with shell access on a VM that holds your provider tokens. **Read [`docs/threat-model.md`](docs/threat-model.md) before running it.**

The VM has an ephemeral external IPv4 (for `apt`/`npm`/Tailscale fetches on first boot) but is **only reachable on `:22`/`:8642` via your Tailscale tailnet** — the VPC firewall denies all ingress from `0.0.0.0/0`, and that deny-all rule is what carries the security guarantee. A future paranoid mode replaces the external IP with Cloud NAT + an egress allowlist. See [`docs/security.md`](docs/security.md).

## Prerequisites

- `gcloud` CLI, authenticated to a billing-enabled GCP project you own
- `terraform` ≥ 1.7
- A [Tailscale](https://tailscale.com) account, plus the ability to mint a [reusable auth key](https://login.tailscale.com/admin/settings/keys)
- A modern Bash (5+) and `git`
- macOS or Linux (Windows via WSL2 is untested)

## Quickstart

```bash
git clone https://github.com/NishantEC/herm.git
cd herm
make install                            # symlink bin/herm into ~/.local/bin
gcloud auth application-default login    # Terraform's GCS backend needs ADC
herm init                               # one-time; writes ~/.config/herm/config.toml
# Mint a single-use ephemeral Tailscale auth key (no tags) at
# https://login.tailscale.com/admin/settings/keys, then:
herm up                                 # paste the key when prompted; ~8 min cold boot
herm ssh                                # tailscale ssh herm@herm-vm (no sudo by design)
```

Then log Hermes into an LLM provider from the VM:

```bash
hermes model    # OAuth (Claude Pro/Max) or API-key auth
hermes          # chat
```

For maintenance that needs `sudo` (logs, systemctl), use the Google OS Login path:

```bash
gcloud compute ssh herm-vm --zone us-central1-a --project <your-project> --tunnel-through-iap
```

## Reaching the gateway

The Hermes gateway is OpenAI-compatible. From any device on your tailnet:

```bash
TOKEN=$(tailscale ssh herm@herm-vm cat ~/.hermes/.api-token)
curl -sS http://herm-vm:8642/v1/chat/completions \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"hi"}],"max_tokens":50}'
```

On a phone, `herm qr` prints a terminal QR code with the gateway URL + token for OpenAI-compatible chat clients.

## Commands

| Command | Effect |
|---|---|
| **Lifecycle** | |
| `herm init` | Configure `~/.config/herm/config.toml`, enable GCP APIs, create the Terraform state bucket. One-time. |
| `herm up [--replace-vm]` | `terraform apply`. `--replace-vm` force-recreates the VM (keeps disk + secret). |
| `herm down` | `terraform destroy` of the VM + ephemeral resources. **Persistent disk and backup bucket survive.** |
| `herm nuke` | Destroy everything, including the persistent disk and GCS backup (double-confirms). |
| `herm status` | Uptime, tailnet name, last backup time. |
| **Day-to-day** | |
| `herm ssh` | `tailscale ssh herm@herm-vm`. |
| `herm logs <unit>` | Tail journald for a systemd unit on the VM. |
| `herm open <target>` | Open hermes / health / console / tailscale URLs in your browser. |
| `herm qr` | Print a terminal QR code with the gateway URL + token (for phone clients). |
| **Skills** | |
| `herm skills list` | Show installed skills, source, and enabled/live state. |
| `herm skills sync` | Reconcile the VM to the lockfile and reload the gateway. |
| `herm skills enable\|disable <name>` | Toggle a skill, reconcile, reload. |
| `herm skills deploy` | Push the engine + catalog to the VM (herm-owned, no root). |
| **Auth** | |
| `herm login <provider>` | OAuth/device-code flow on the VM (`claude`, `gh`, `gemini`, `codex`, `opencode`, `goose`, `all`). |
| **Maintenance** | |
| `herm rotate [hermes]` | Rotate the Hermes API server token. See [`docs/rotation.md`](docs/rotation.md). |
| `herm upgrade` | Snapshot disk, pull latest versions, restart, auto-rollback on failure. |
| `herm backup [now\|list]` | Trigger an immediate GCS rsync, or list dated backup folders. |
| `herm restore <YYYY-MM-DD>` | Restore `/home/herm` from a dated backup snapshot. |
| `herm console` | Open the GCP console page for the VM. |

## Skills

Skills tell the agent how to handle specific kinds of requests. `herm` ships 6, seeded into Hermes at boot and matched against incoming prompts by their `description:` line:

| Skill | Fires on | Schedule |
|---|---|---|
| `debug` | Errors, stack traces, "something is broken" | on-demand |
| `review-pr` | PR URLs, "review PR X" | on-demand |
| `write-doc` | "write a doc", "explain Y in the README" | on-demand |
| `update-deps` | "bump deps", "upgrade X" | on-demand |
| `watch-repo` | (heartbeat) | every 30 min |
| `summarize-day` | (heartbeat) | 09:00 UTC daily |

Manage them from your laptop with `herm skills` — the herm-owned `skillpm` engine self-deploys over SSH (no root, no reprovision), reconciles the live set from a lockfile, and reloads the gateway on changes. See [`docs/skills.md`](docs/skills.md) for the `SKILL.md` format, authoring your own, and the tool-allowlist rules.

## Integrations

First boot wires up three integration layers. All are opt-in by token — nothing reaches the network until you paste credentials.

- **CLI fleet** — `claude`, `gh`, `gemini`, `codex`, `opencode` are installed into the `herm` user's `~/.local/bin`; log each in with `herm login <provider>`.
- **MCP servers** — Asana, Linear, and Figma are registered in `~/.hermes/config.yaml` via community stdio servers. Tokens seed as `PASTE_PAT_HERE`; fill them in (`mcp_servers.<name>.env.*`) and a server without a token simply fails soft at startup.
- **Slack** — the `slack` toolset is enabled (Socket Mode) but dormant until you set `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, and `SLACK_ALLOWED_USERS` in `~/.hermes/.env`. Hermes is **deny-all**, so `SLACK_ALLOWED_USERS` is required. See [`docs/integrations/slack.md`](docs/integrations/slack.md).

After editing `~/.hermes/config.yaml`/`.env`, reload the gateway: `pkill -TERM -f 'hermes gateway'` (systemd respawns it).

## Repository layout

| Path | What's there |
|---|---|
| [`bin/herm`](bin/herm), [`cli/`](cli/) | The `herm` CLI dispatcher and subcommands. |
| [`terraform/`](terraform/) | VPC, firewall, VM, disk, GCS backup, IAM, secrets. |
| [`cloud-init/scripts/`](cloud-init/scripts/) | Ordered first-boot setup steps (inlined into the GCE startup script). |
| [`skillpm/`](skillpm/), [`skills/`](skills/) | The skill package-manager engine and the shipped skill catalog. |
| [`systemd/`](systemd/) | Gateway, nightly backup, and idle-reaper units. |
| [`docs/`](docs/) | Threat model, security, cost, rotation, skills, integrations, and design specs. |

## Design docs

- [v0.1 foundation](docs/superpowers/specs/2026-05-13-herm-design.md)
- [v0.2 additions + the Multica pivot](docs/superpowers/specs/2026-05-13-herm-v0.2-design.md)
- [`herm skills` package manager](docs/superpowers/specs/2026-05-31-herm-skills-package-manager-design.md)

## Contributing

Bug reports and PRs welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). For security issues, please open a private GitHub advisory (see [`SECURITY.md`](SECURITY.md)).

## License

MIT — see [`LICENSE`](LICENSE).
