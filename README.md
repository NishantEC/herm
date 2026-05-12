# herm

> Headless AI agent workstation on Google Cloud, tunneled to your devices via Tailscale.

**⚠️ v0.2.0 — early but working.** Provisions a small GCP VM running [Hermes Agent](https://github.com/nousresearch/hermes-agent) v0.13.0, joins it to your tailnet, serves the OpenAI-compatible gateway at `:8642`, seeds 6 custom skills (`debug`, `review-pr`, `write-doc`, `update-deps`, `watch-repo`, `summarize-day`), and applies a hardening policy that disables 15 Hermes toolsets (full Chrome DevTools, computer-use, external messaging, etc.) by default.

---

### Cost

`herm` runs a real GCP VM. Expect **~$13/month at idle** plus your LLM API costs. Set a [GCP budget alert](https://cloud.google.com/billing/docs/how-to/budgets) before running this — `herm` configures one at $25/mo by default, but you should pick your own ceiling.

### Security

`herm` installs an autonomous AI agent with shell access on a VM that will hold your GitHub OAuth token (in later versions). Read [`docs/threat-model.md`](docs/threat-model.md) before running this.

The VM has an ephemeral external IPv4 (for apt/npm/Tailscale package fetches on first boot) but is **only reachable on `:22`/`:8642` via your Tailscale tailnet** — the VPC firewall denies all ingress from `0.0.0.0/0` and the deny-all rule is what carries the security guarantee. v0.4 paranoid mode reverts to no external IP + Cloud NAT + egress allowlist. See [`docs/security.md`](docs/security.md).

---

## Prerequisites

- `gcloud` CLI (authenticated to a billing-enabled GCP project you own)
- `terraform` ≥ 1.7
- `tailscale` (account, plus a [reusable auth-key generator](https://login.tailscale.com/admin/settings/keys) you can run on demand)
- A modern Bash (5+) and `git`
- macOS or Linux (Windows via WSL2 — untested in v0.1)

## Quickstart

```bash
git clone https://github.com/NishantEC/herm.git
cd herm
make install                                # symlinks bin/herm into ~/.local/bin
gcloud auth application-default login       # Terraform's GCS backend needs ADC
herm init                                   # one-time; writes ~/.config/herm/config.toml
# Generate a single-use ephemeral Tailscale auth key at
# https://login.tailscale.com/admin/settings/keys (no tags), then:
herm up                                     # paste the key when prompted; ~8 min cold boot
tailscale ssh herm@herm-vm                  # you're in (as the herm user, no sudo)
```

After the VM is up you'll need to log Hermes into an LLM provider. From the tailscale SSH session:

```bash
hermes model              # walks you through OAuth (Claude Pro/Max) or API-key auth
hermes                    # chat
```

For maintenance commands that need sudo (logs, systemctl), use the Google-OS-Login path from your laptop:

```bash
gcloud compute ssh herm-vm --zone us-central1-a --project <your-project> --tunnel-through-iap
```

That lands you as a Google-identity user with sudo permitted.

## Reaching the gateway

The Hermes gateway is OpenAI-compatible. From any device on your tailnet:

```bash
TOKEN=$(tailscale ssh herm@herm-vm cat ~/.hermes/.api-token)
curl -sS -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"model":"hermes-agent","messages":[{"role":"user","content":"hi"}],"max_tokens":50}' \
  http://herm-vm:8642/v1/chat/completions
```

## Subcommands

| Command | Effect |
|---|---|
| **Lifecycle** | |
| `herm init` | Configure `~/.config/herm/config.toml`, enable GCP APIs, create the Terraform state bucket. One-time. |
| `herm up [--replace-vm]` | `terraform apply`. `--replace-vm` force-recreates the VM (keeps disk + secret). |
| `herm down` | `terraform destroy` of the VM + ephemeral resources. **Persistent disk and backup bucket survive.** |
| `herm nuke` | Destroys everything including persistent disk and GCS backup (double-confirms). |
| `herm status` | Uptime, tailnet name, last backup time. |
| **Day-to-day** | |
| `herm ssh` | `tailscale ssh herm@herm-vm`. |
| `herm logs <unit>` | Tail journald for a systemd unit on the VM. |
| `herm open <target>` | Open hermes / health / console / tailscale URLs in default browser. |
| `herm qr` | Print a terminal QR code with the gateway URL + bearer token (for phone clients). |
| **Auth** | |
| `herm login <provider>` | OAuth/device-code flow on the VM. Providers: `claude`, `gh`, `gemini`, `codex`, `opencode`, `goose`, `all`. |
| **Maintenance** | |
| `herm rotate [hermes]` | Rotate the Hermes API server token. See [`docs/rotation.md`](docs/rotation.md). |
| `herm upgrade` | Snapshot disk, pull latest versions, restart, auto-rollback on failure. |
| `herm backup [now\|list]` | Trigger an immediate GCS rsync, or list dated backup folders. |
| `herm restore <YYYY-MM-DD>` | Restore `/home/herm` from a dated backup snapshot. |
| `herm console` | Open the GCP console page for the VM. |

## Skills

`herm` seeds 6 skills into Hermes at boot. They live as YAML-frontmatter Markdown under `~/.hermes/skills/herm/` and Hermes matches incoming prompts against their `description:` line.

| Skill | Fires on | Schedule |
|---|---|---|
| `debug` | Errors, stack traces, "something is broken" | on-demand |
| `review-pr` | PR URLs, "review PR X" | on-demand |
| `write-doc` | "write a doc," "explain Y in README" | on-demand |
| `update-deps` | "bump deps," "upgrade X" | on-demand |
| `watch-repo` | (no trigger — heartbeat) | every 30 min |
| `summarize-day` | (no trigger — heartbeat) | 09:00 UTC daily |

See [`docs/skills.md`](docs/skills.md) for the format, how to add your own, and the tool-allowlist intersection rules.

## Architecture

See [`docs/superpowers/specs/2026-05-13-herm-design.md`](docs/superpowers/specs/2026-05-13-herm-design.md) for the v0.1 foundation, and [`docs/superpowers/specs/2026-05-13-herm-v0.2-design.md`](docs/superpowers/specs/2026-05-13-herm-v0.2-design.md) for the v0.2 additions and the Multica pivot rationale.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Bug reports and PRs welcome. Security issues: please use a private GitHub advisory — see [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE).
