# herm — Design Spec

**Date:** 2026-05-13
**Status:** Draft (brainstorm output, pre-implementation-plan)
**Owner:** Nishant Gupta

---

## 1. Purpose

`herm` provisions a personal, headless AI agent workstation on Google Cloud Platform — a small persistent VM that runs a single agent identity (`nishant-agent`) accessible from the owner's laptop and phone via Tailscale. The agent has a ticket queue, scheduled heartbeats, compounding skills, and budget tracking. It uses a fleet of OAuth-authenticated coding CLIs (`claude`, `gh`, `gemini`, `codex`, `opencode`, `goose`) as its tools, with Hermes Agent as the always-on brain and Multica as the user-facing orchestration layer.

The repository will be open-sourced under MIT so others can run their own.

## 2. Goals

- **One persistent agent identity.** Externally a single voice ("me as an agent"); internally, Multica skills dispatch focused subagent contexts per task (debug, review-pr, write-doc, etc.).
- **Phone + laptop access.** Same Tailscale URL from either device; browser-only on phone, native client optional on laptop.
- **Survives lifecycle churn.** `herm down` followed by `herm up` weeks later restores memory, OAuth credentials, skills, ticket history — nothing is lost.
- **Cheap to idle.** ~$13/mo GCP at rest plus LLM costs (most of which stay inside subscription tiers via OAuth'd CLIs).
- **Secure by default.** No external IP, IAM-scoped service account, no sudo for agents, no credentials in the public repo, watchdogs and budget alerts on.
- **Forkable.** A stranger should be able to clone the repo, read it in under an hour, and stand up their own without finding any hardcoded reference to the maintainer's project.

## 3. Non-goals

- **No multi-cloud abstraction in v1.** GCP only. AWS/Azure variants deferred.
- **No agent team / org chart.** Not Paperclip-shaped. One visible identity.
- **No public HTTPS endpoint.** Tailscale only. Cloudflare Tunnel deferred to an optional `herm expose` future subcommand.
- **No managed SaaS offering.** This is infrastructure-as-code that the owner runs in their own GCP project. No central control plane.
- **No telemetry.** Now or in v1.
- **No one-line `curl | sh` installer.** Security-sensitive tool; require the user to clone and read.

## 4. Architecture

```
Laptop / Phone                        Tailnet                       GCP project
                                                                    ┌──────────────────────────────────┐
[ browser ] ─────────────────────────────────────────────────────► │  VM (e2-small, Debian 12)        │
[ Hermes Desktop ] ───► https://herm-vm:8642 ──────────────────►   │   • multica           :3000 (UI) │
[ tailscale ssh ] ────► herm-vm ───────────────────────────────►   │   • hermes-agent      :8642      │
                                                                    │   • hermes-workspace  :8643      │
                                                                    │   • ttyd              :7681      │
                                                                    │   • CLI fleet (claude, gh,       │
                                                                    │     gemini, codex, opencode,     │
                                                                    │     goose) — OAuth'd, tokens     │
                                                                    │     on persistent disk           │
                                                                    │                                  │
                                                                    │  Attached PD-SSD 10GB            │
                                                                    │   mounted at /home/herm          │
                                                                    │   ├ .hermes/                     │
                                                                    │   ├ .multica/                    │
                                                                    │   ├ .config/{claude,gh,…}/       │
                                                                    │   └ workspaces/                  │
                                                                    │                                  │
                                                                    │  Service account ──► Secret      │
                                                                    │                       Manager    │
                                                                    │                       (TS auth   │
                                                                    │                        key,      │
                                                                    │                        Hermes    │
                                                                    │                        API tok)  │
                                                                    │                                  │
                                                                    │  systemd timer ──► GCS bucket    │
                                                                    │   nightly rsync of /home/herm    │
                                                                    │   (object versioning enabled)    │
                                                                    └──────────────────────────────────┘
```

### 4.1 Component roles

| Component | Role | Port | Surface |
|---|---|---|---|
| **Multica** | Orchestration layer: tickets, heartbeats/schedules, skills registry, budget tracking | 3000 | Primary web UI (laptop browser + phone browser) |
| **Hermes Agent** | The brain. Persistent memory, reasoning, tool use, API server. Registered as Multica's agent. | 8642 | API (consumed by Multica and Hermes Desktop) |
| **Hermes Workspace** | Native web workspace for deep Hermes-specific operations (terminal, memory inspector, skills view) | 8643 | Secondary web UI |
| **ttyd** | Browser-accessible tmux session for SSH-equivalent operations from a phone | 7681 | Fallback / power-user surface |
| **Hermes Desktop** | Native macOS/Windows/Linux client (lives on the laptop, not the VM) pointing at remote Hermes API | — | Optional, native streaming chat |
| **CLI fleet** | `claude`, `gh`, `gemini`, `codex`, `opencode`, `goose` — invoked by Hermes as subprocesses | — | Internal |

### 4.2 Agent identity model (A2 — single face, invisible subagents)

There is one user-visible agent: **`nishant-agent`**, registered in Multica with Hermes Agent as its execution brain. The skill registry is owned by Multica (Multica is the orchestration layer); Hermes provides the persistent memory and the reasoning loop that runs underneath each skill invocation. Skill definitions live under `/home/herm/.multica/skills/*.yaml` on the persistent disk and are seeded from the repo's `skills/` directory on first boot. Each skill bundles:

- A focused system prompt
- A tool allowlist (subset of the CLI fleet + shell commands)
- A memory scope (per-skill, per-project, or shared with the global memory)
- A model preference (e.g., Claude for reasoning-heavy debug, Gemini for big-context refactors)
- Optional schedule (cron string)
- Optional budget cap

Initial skills shipped (placeholders the user can edit/extend on the VM):

- `debug` — Claude Code, narrow shell + read/write to the active repo
- `review-pr` — Claude Code, read-only repo + `gh`, posts a PR comment
- `write-doc` — Claude, file-write only under `docs/`, no shell
- `update-deps` — Claude Code, runs in a git worktree, opens a PR rather than committing to main
- `watch-repo` — `gh` only, heartbeat every 30 min, pings the user when an interesting event lands
- `summarize-day` — heartbeat at 09:00 daily; reads yesterday's memory + `gh` notifications, writes a brief into the agent's inbox

When the user messages `nishant-agent` ("review this PR"), Multica routes the ticket, Hermes selects the matching skill, the skill is invoked as a focused subagent run, the result rolls back into the primary conversation. The user never sees the skill as a separate agent row.

## 5. Security model

### 5.1 Essential controls (always on, baked into `herm up`)

**Network exposure**

- VM has no external IP. Only reachable on the tailnet.
- VPC firewall denies all ingress by default. Egress open.
- Tailscale ACL locks the VM to tagged owner devices only, on `:22`, `:3000`, `:7681`, `:8642`, `:8643`.
- Tailscale auth key is a single-use ephemeral key (configured with `reusable=false`, `ephemeral=true`); the VM joins as an ephemeral node that auto-removes from the tailnet on disconnect. Cloud-init deletes the Secret Manager entry after a successful join.

**Identity**

- Dedicated `herm-vm` service account. Scoped IAM: `secretmanager.secretAccessor` on specific secrets only; `storage.objectAdmin` on the one backup bucket only. No project-level roles.
- OS Login enabled. SSH is gated by Google identity + 2FA.

**Data at rest**

- All agent processes run as the unprivileged `herm` user (never root). Credentials in `/home/herm/.config/...` with `0700`/`0600`.
- Persistent disk and GCS backup encrypted at rest (Google-managed key by default).
- GCS bucket: uniform bucket-level access, object versioning enabled, private only.
- Secret Manager holds only the Tailscale bootstrap key (auto-deleted post-use) and the Hermes API server token.

**Runtime hardening**

- Each systemd unit runs with: `NoNewPrivileges=true`, `ProtectSystem=strict`, `ProtectHome=read-only` (with `/home/herm` explicitly writable), `PrivateTmp=true`, empty `CapabilityBoundingSet`, `RestrictSUIDSGID=true`, `LockPersonality=true`.
- Agents never get sudo.
- Per-turn wall-clock watchdog: any agent turn running >30 min receives SIGTERM.

**Cost runaway**

- GCP Budget alert configured at $25/mo by default (50/80/100% pings).
- VM machine type locked in Terraform.
- README reminds the owner to set per-provider spend caps in Anthropic/OpenAI/Gemini consoles.

**Supply chain**

- Every installed package pinned to an exact version in cloud-init.
- No `curl | sh` from random hosts. Hashes verified where upstream publishes them.
- Dependabot/Renovate PRs against the repo for version bumps, reviewed by the owner.

**Auditability**

- VM stdout/journald → Cloud Logging, 30-day retention.
- Hermes API access logs persisted to disk + nightly GCS sync.
- GCS Data Access logs enabled on the backup bucket.

**Blast radius**

- `herm down` actually deletes the VM (disk persists). Unused = zero attack surface.
- Disk snapshot taken before `herm upgrade`. One-command rollback.

### 5.2 Paranoid mode (`herm up --paranoid`)

Adds:

- **Cloud NAT egress allowlist** — VM egress restricted to `api.anthropic.com`, `api.openai.com`, `generativelanguage.googleapis.com`, `api.github.com`, plus apt/npm/PyPI mirrors. Prompt-injection-driven exfiltration to arbitrary hosts becomes impossible.
- **CMEK** — Customer-managed KMS keys for the disk, GCS bucket, and Secret Manager. Owner can revoke and instantly brick the environment if compromise is suspected.
- **Per-agent sandboxing** — Each agent runs in a rootless Podman container with `--read-only` root FS, dropped capabilities, separate UID. A prompt-injected `claude` cannot read `gh`'s token.
- **Tool allowlists** — Hermes' toolsets and Claude Code's `allowedTools` are configured to require explicit approval rather than blanket shell.
- **Auto-reaper** — VM auto-deletes after N hours of no tailnet activity from owner devices.
- **API token rotation** — `herm rotate` regenerates the Hermes API token weekly.

Approximate cost delta: +$5–10/mo.

### 5.3 Explicit non-controls (and why)

- **No `chattr +i` on token files** — breaks agents in subtle ways without preventing exfil (only modification).
- **No "review every tool call by hand" default** — that's what `--paranoid` tool allowlists are for; doing it always makes the agent useless.
- **No public HTTPS endpoint with Cloudflare Access** — two auth systems for one box. Deferred to `herm expose` if ever needed.

## 6. `herm` CLI surface

The on-laptop tool. A bash dispatcher; each subcommand is its own file under `cli/commands/<cmd>.sh`. Shells out to `terraform`, `gcloud`, `tailscale`, `ssh`. No new runtime required on the laptop.

```
# Lifecycle
herm init                  # one-time: configure ~/.config/herm/config.toml, enable GCP APIs, create state bucket
herm up [--paranoid]       # terraform apply
herm down                  # terraform destroy of VM + ephemeral resources; persistent disk survives
herm nuke                  # destroys everything including PD-SSD and GCS backup (double-confirms)
herm status                # uptime, tailnet name, last backup, current month-to-date cost

# Day-to-day
herm ssh                   # `tailscale ssh herm@herm-vm`, drops into tmux
herm open [multica|hermes|ttyd]   # opens the chosen UI in default browser
herm logs <unit>           # tails journald for the named systemd unit

# First-run auth
herm login claude          # SSH in, run `claude login`, complete OAuth in laptop browser
herm login gh
herm login gemini
herm login codex
herm login all             # runs all of the above sequentially

# Maintenance
herm backup now            # forces a GCS rsync immediately
herm restore <timestamp>   # restores /home/herm from a backup snapshot
herm upgrade               # snapshots disk, pulls latest pinned versions, restarts units
herm rotate                # regenerates Hermes API token, restarts, prints new token for Hermes Desktop

# Mobile
herm qr                    # prints a terminal QR code with the Multica URL — scan from phone

# Escape hatch
herm console               # opens GCP console for the VM
```

## 7. Repository layout

```
herm/
├─ LICENSE                          # MIT
├─ README.md                        # see §8
├─ SECURITY.md                      # private GH advisory reporting
├─ CONTRIBUTING.md
├─ CODE_OF_CONDUCT.md               # Contributor Covenant 2.1
├─ CHANGELOG.md                     # Keep a Changelog format
├─ .github/
│  ├─ CODEOWNERS
│  ├─ ISSUE_TEMPLATE/{bug,feature,security}.yml
│  ├─ PULL_REQUEST_TEMPLATE.md
│  ├─ dependabot.yml
│  └─ workflows/
│     ├─ ci.yml                     # shellcheck, terraform fmt/validate, tflint, markdownlint
│     ├─ trivy.yml                  # IaC + dependency scan
│     ├─ gitleaks.yml               # secret scan on PRs
│     └─ release.yml                # tag → GitHub Release with changelog excerpt
├─ Makefile                         # `make install` symlinks bin/herm into ~/.local/bin
├─ bin/
│  └─ herm                          # dispatcher
├─ cli/
│  ├─ lib.sh                        # shared helpers
│  └─ commands/                     # one file per subcommand from §6
│     ├─ init.sh
│     ├─ up.sh
│     ├─ down.sh
│     ├─ nuke.sh
│     ├─ status.sh
│     ├─ ssh.sh
│     ├─ open.sh
│     ├─ logs.sh
│     ├─ login.sh
│     ├─ backup.sh
│     ├─ restore.sh
│     ├─ upgrade.sh
│     ├─ rotate.sh
│     ├─ qr.sh
│     └─ console.sh
├─ terraform/
│  ├─ main.tf                       # VM, PD-SSD, service account, firewall, optional Cloud NAT
│  ├─ secrets.tf                    # Secret Manager entries
│  ├─ network.tf                    # VPC, subnet, firewall rules, paranoid-mode Cloud NAT
│  ├─ backup.tf                     # GCS bucket, versioning, lifecycle, audit logging
│  ├─ variables.tf                  # region, machine_type, paranoid flag, tailscale auth key
│  ├─ outputs.tf
│  └─ backend.tf                    # GCS remote state, parameterized bucket name
├─ cloud-init/
│  ├─ cloud-init.yaml
│  └─ scripts/
│     ├─ 01-mount-disk.sh
│     ├─ 02-install-cli-tools.sh    # claude, gh, gemini, codex, opencode, goose at pinned versions
│     ├─ 03-install-hermes.sh
│     ├─ 04-install-multica.sh
│     ├─ 05-install-ttyd.sh
│     ├─ 06-tailscale-join.sh
│     └─ 99-systemd-units.sh
├─ systemd/
│  ├─ multica.service
│  ├─ hermes-agent.service
│  ├─ hermes-workspace.service
│  ├─ ttyd.service
│  ├─ herm-backup.service
│  └─ herm-backup.timer
├─ tailscale/
│  └─ acl.hujson.example            # placeholder tags, MUST be replaced
├─ skills/                          # initial skill templates the agent registers on first boot
│  ├─ debug.yaml
│  ├─ review-pr.yaml
│  ├─ write-doc.yaml
│  ├─ update-deps.yaml
│  ├─ watch-repo.yaml
│  └─ summarize-day.yaml
├─ examples/
│  ├─ config.toml.example           # ~/.config/herm/config.toml template
│  ├─ terraform.tfvars.example
│  └─ env.example
└─ docs/
   ├─ superpowers/specs/            # this design doc lives here
   ├─ threat-model.md
   ├─ security.md
   ├─ cost.md
   ├─ cli.md
   ├─ skills.md
   └─ troubleshooting.md
```

### 7.1 Personal config isolation

Nothing in the repo contains the owner's GCP project ID, billing account, region preference, tailnet name, or any credential. All of that lives in `~/.config/herm/config.toml`, created by `herm init` from `examples/config.toml.example`.

The Terraform backend bucket name is parameterized to `${project_id}-herm-tfstate` so two strangers running `herm` in different projects never collide.

## 8. README structure

A stranger landing on the GitHub page should see, in order:

1. One-line pitch — "Headless AI agent workstation on GCP, tunneled to your devices via Tailscale."
2. Cost banner — `⚠️ ~$13/mo GCP at idle + your LLM costs. Set a GCP budget alert before running this.`
3. Security banner — `⚠️ Installs autonomous AI agents with shell access on a VM holding your GitHub OAuth token. Read docs/threat-model.md before running this.`
4. Prerequisites — `gcloud`, `terraform`, `tailscale`, a billing-enabled GCP project, a Tailscale account.
5. Quickstart — five commands maximum.
6. Architecture diagram (the one in §4).
7. Subcommand reference — link to `docs/cli.md`.
8. Cost breakdown — link to `docs/cost.md`.
9. Security overview — links to `docs/security.md` and `docs/threat-model.md`.
10. Contributing — link to `CONTRIBUTING.md`.

## 9. Bootstrap flow

### 9.1 `herm init` (one-time, ~3 min)

1. Prompt for GCP project ID, billing account, preferred region (default `us-central1`), Tailscale tailnet name.
2. Write `~/.config/herm/config.toml`.
3. `gcloud services enable compute.googleapis.com secretmanager.googleapis.com storage.googleapis.com iap.googleapis.com cloudkms.googleapis.com` (KMS only if `--paranoid`).
4. Create the GCS bucket for Terraform state (`${project_id}-herm-tfstate`).
5. Prompt the owner to mint a Tailscale ephemeral auth key (URL-linked instructions) and paste it. Store in Secret Manager.
6. Print next steps.

### 9.2 `herm up` (cold ~8 min, warm ~3 min)

1. Read `~/.config/herm/config.toml`.
2. `terraform apply` provisions: VPC, subnet, firewall rules, optional Cloud NAT (paranoid), service account, IAM bindings, PD-SSD (or reuses existing), Secret Manager entries, VM with cloud-init user-data referencing the secrets.
3. Cloud-init on the VM: mounts PD-SSD at `/home/herm`, installs pinned versions of all packages, drops systemd units, joins the tailnet using the ephemeral key (which is then deleted from Secret Manager by the cloud-init exit step), starts services.
4. The laptop `herm` CLI polls Tailscale until `herm-vm` is reachable, then prints the Multica URL.

### 9.3 First-run auth (~5 min)

```
herm login all
```

Sequentially SSHes into the VM and runs each CLI's native OAuth flow (device code or URL). The owner completes each one in a laptop browser. OAuth tokens land on the persistent disk under `/home/herm/.config/...` and survive `herm down`/`herm up` cycles.

### 9.4 Subsequent `herm up` cycles

OAuth tokens, Hermes memory, Multica tickets, skills, and the apt package cache all live on the persistent disk. Reattaching the disk reduces cold-boot to a few minutes — most of cloud-init becomes "yes, that's already installed at the right version, skip."

## 10. Cost breakdown (default, non-paranoid)

| Item | Approx. monthly |
|---|---|
| `e2-small` VM (730h) | ~$11.00 |
| 10GB PD-SSD | ~$1.70 |
| GCS backup bucket (10GB, nightly versions, ~30-day retention) | <$0.20 |
| Secret Manager (2 secrets) | ~$0.12 |
| Cloud Logging (30-day retention, low volume) | <$0.50 |
| Network egress (low for chat-style API traffic) | <$0.50 |
| **GCP subtotal (idle)** | **~$14/mo** |
| LLM costs | Depends; mostly $0 if staying inside subscription tiers via `claude` / `gemini` / `gh copilot` |

Paranoid mode adds: Cloud NAT (~$5/mo idle + traffic), KMS keys (~$0.06/key/mo), Podman runtime overhead (compute, not billing). Roughly +$5–10/mo total.

## 11. CI / lint pipeline

Run on every PR and on `main`:

- `shellcheck` over every bash file (warnings fail the build).
- `terraform fmt -check`, `terraform validate`, `tflint`.
- `trivy config terraform/` for IaC misconfigurations.
- `gitleaks` for accidental key commits.
- `markdownlint` on docs.

## 12. Open questions / deferred decisions

- **AionUI inclusion** — currently dropped because Multica covers the multi-agent face. Could be added later as an optional UI surface; deferred.
- **OpenClaw inclusion** — the chat-app gateway angle (message your agent from WhatsApp/Telegram). Compelling but deferred until v0.x is stable.
- **Cloudflare Tunnel / public HTTPS** — a `herm expose` subcommand that publishes a Tailscale Funnel or Cloudflare Tunnel endpoint with Cloudflare Access. Deferred.
- **Multi-cloud (AWS/Azure)** — deferred indefinitely. The Terraform module structure should be portable in principle; no work to make it actually portable in v1.
- **A1 → A3 promotion path** — if a Multica skill grows into something the owner wants to interact with as a peer (separate row in the UI), the design supports promoting a skill to a visible agent. No code work needed in v1.

## 13. Success criteria for v1

- A stranger can clone the repo, read the README, and have a working `nishant-agent`-shaped setup in their own GCP project in under 30 minutes.
- The owner can `herm down`, take a 2-week vacation, `herm up`, and find all memory/skills/tickets/OAuth credentials still in place.
- The agent can be productively used from a phone over LTE via the Multica web UI.
- `herm nuke` leaves no GCP resources, no GCS buckets, no Secret Manager entries.
- A `--paranoid` deployment passes `trivy config terraform/` with no high-severity findings.
