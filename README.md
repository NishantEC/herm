# herm

> Headless AI agent workstation on Google Cloud, tunneled to your devices via Tailscale.

**⚠️ v0.1.0 — early but working.** Provisions a small GCP VM running [Hermes Agent](https://github.com/nousresearch/hermes-agent) v0.13.0, joins it to your tailnet, and serves the OpenAI-compatible gateway at `:8642` with bearer auth. Multica orchestration, the full skills system, and paranoid-mode hardening land in v0.2–v0.4.

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

## Subcommands (v0.1)

| Command | Effect |
|---|---|
| `herm init` | Configure `~/.config/herm/config.toml`, enable GCP APIs, create the Terraform state bucket. One-time. |
| `herm up` | `terraform apply` — provisions the VM, joins the tailnet. |
| `herm up --replace-vm` | Force-recreates only the VM (keeps disk, secret). Use when iterating on cloud-init/startup-script. |
| `herm down` | `terraform destroy` of the VM + ephemeral resources. **Persistent disk and backup bucket survive.** |
| `herm nuke` | Destroys everything including persistent disk and GCS backup (double-confirms). |
| `herm status` | Uptime, tailnet name, last backup time. |
| `herm ssh` | `tailscale ssh herm@herm-vm`. |

## Architecture (v0.1 surface)

See [`docs/superpowers/specs/2026-05-13-herm-design.md`](docs/superpowers/specs/2026-05-13-herm-design.md) for the full design.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Bug reports and PRs welcome. Security issues: please use a private GitHub advisory — see [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE).
