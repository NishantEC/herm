# herm

> Headless AI agent workstation on Google Cloud, tunneled to your devices via Tailscale.

**⚠️ v0.1 — early/experimental.** Provisions a small GCP VM running [Hermes Agent](https://github.com/nousresearch/hermes-agent). Multica orchestration, the full skills system, and paranoid-mode hardening land in v0.2–v0.4.

---

### Cost

`herm` runs a real GCP VM. Expect **~$13/month at idle** plus your LLM API costs. Set a [GCP budget alert](https://cloud.google.com/billing/docs/how-to/budgets) before running this — `herm` configures one at $25/mo by default, but you should pick your own ceiling.

### Security

`herm` installs an autonomous AI agent with shell access on a VM that will hold your GitHub OAuth token (in later versions). Read [`docs/threat-model.md`](docs/threat-model.md) before running this.

The VM has no public IP and is only reachable via your Tailscale tailnet. See [`docs/security.md`](docs/security.md) for the full controls list.

---

## Prerequisites

- `gcloud` CLI (authenticated to a billing-enabled GCP project you own)
- `terraform` ≥ 1.7
- `tailscale` (account, plus a [reusable auth-key generator](https://login.tailscale.com/admin/settings/keys) you can run on demand)
- A modern Bash (5+) and `git`
- macOS or Linux (Windows via WSL2 — untested in v0.1)

## Quickstart

```bash
git clone https://github.com/<yourname>/herm.git
cd herm
make install                   # symlinks bin/herm into ~/.local/bin
herm init                      # one-time: configures ~/.config/herm/config.toml
herm up                        # provisions the VM (~8 min)
tailscale ssh herm@herm-vm     # you're in
```

## Subcommands (v0.1)

| Command | Effect |
|---|---|
| `herm init` | Configure `~/.config/herm/config.toml`, enable GCP APIs, create the Terraform state bucket. One-time. |
| `herm up` | `terraform apply` — provisions the VM, joins the tailnet. |
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
