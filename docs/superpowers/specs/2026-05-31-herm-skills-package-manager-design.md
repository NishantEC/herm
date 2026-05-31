# Design: `herm skills` — a skill package manager

**Status:** Approved (design) — pending implementation plan
**Date:** 2026-05-31
**Supersedes:** the boot-only skill seeding in `cloud-init/scripts/07-seed-skills.sh`

## Context

Today every skill this repo ships lives in `skills/` and is `rsync`'d as one flat
bundle into `~/.hermes/skills/herm/` on each boot by `cloud-init/scripts/07-seed-skills.sh`
(`rsync -a --delete` scoped to the `herm/` namespace; user-authored skills elsewhere
are preserved). This is all-or-nothing: you cannot install a subset, install a skill
someone else published, toggle one off, or manage skills without a full `herm up`.

Several shipped skills are *correlated*: four of six (`review-pr`, `update-deps`,
`watch-repo`, `summarize-day`) depend on the `gh` CLI; the two heartbeats
(`watch-repo`, `summarize-day`) are a pair; `debug`/`write-doc`/`update-deps` cluster
around file edits. Installing one usefully often implies wanting its siblings and the
CLIs it calls.

## Goals

- A `herm skills` CLI that installs, removes, enables/disables, and inspects skills
  **at runtime** against the live VM — not only at boot.
- Install skills from **anywhere**: this repo's catalog, a local directory, a remote
  git URL, or a named registry entry. (A real package manager.)
- **Hybrid state** (npm model): the CLI mutates the live VM for instant effect *and*
  updates a declarative lockfile that reproduces the skill set on a fresh VM.
- **npm-style transitive dependency resolution**: installing a skill pulls its declared
  sibling skills and missing fleet CLIs; for MCP servers / Hermes toolsets that need
  owner-supplied tokens, it *warns* rather than auto-editing.

## Non-goals

- A hosted registry service. The "registry" is a static index file (see §5).
- Sandboxing skill execution beyond Hermes' existing tool-allowlist intersection.
- Changing how Hermes itself discovers skills (still `~/.hermes/skills/herm/`).
- Replacing user-authored skills outside the `herm/` namespace (left untouched).

## Decisions (locked during brainstorming)

| Axis | Decision |
|---|---|
| Interface | A `herm skills` subcommand (laptop CLI acting on the VM over `tailscale ssh`). |
| Sources | Package manager: catalog + local dir + remote git + registry name. |
| State | Hybrid — live VM mutation **and** a declarative lockfile (reproducible). |
| Dependencies | Auto-resolve: pull sibling skills + missing fleet CLIs; warn (don't auto-edit) for MCP/toolsets. |
| Build approach | Python engine on the VM (`skillpm`) + thin bash CLI; the same engine runs at boot. |

## Architecture

Three components:

1. **`skillpm` — the engine (Python, on the VM).** Shipped from the repo to
   `/opt/herm/skillpm/` and run with Hermes' venv interpreter
   (`~/.hermes/hermes-agent/venv/bin/python`), which already has `pyyaml`. It is the
   canonical reader **and** writer of the lockfile: it reads TOML with `tomllib`
   (Python 3.11+) or a vendored `tomli`, and **emits** TOML by rendering the flat
   schema directly (stdlib ships no TOML writer; hand-rolling the emit matches the
   repo's existing hand-rolled-TOML stance). Responsibilities: resolve a source to skill files, parse
   `SKILL.md` frontmatter, build and walk the `requires` dependency graph, reconcile
   `~/.hermes/skills/herm/` to the lockfile, install missing fleet CLIs, emit
   actionable warnings for MCP/toolset deps. This is the single code path used by
   **both** the boot reconciler and the CLI.

2. **`cli/commands/skills.sh` — the bash wrapper (laptop).** Mirrors `login.sh`'s
   transport: reads `tailscale hostname` from `~/.config/herm/config.toml` via
   `herm::read_config`, ships subcommands to the VM with
   `tailscale ssh "herm@$host" -- <venv-python> /opt/herm/skillpm <args>`. It **stores
   and ferries** the local lockfile (`~/.config/herm/skills.toml`) but does not parse
   it — the engine is canonical; the wrapper still uses `herm::read_config` only for
   `config.toml` (hostname). Mutating commands push the lockfile to the VM, run the
   engine, then pull the engine-emitted lockfile back on success. Registered in
   `bin/herm`'s dispatch case-list and a new `SKILLS` help
   group.

3. **`skills.toml` — the declarative lockfile.** Source of truth at
   `~/.config/herm/skills.toml` (version-controllable, the "package.json + lock"),
   mirrored to `~/.hermes/skills/herm/skills.toml` on the VM. npm model: edit + apply.

```
laptop                                  VM
------                                  --
herm skills add <x>                     /opt/herm/skillpm  (engine)
  └─ resolve local/git/registry  ──ssh──▶  fetch + parse + dep-resolve
  └─ push ~/.config/herm/skills.toml ──▶  ~/.hermes/skills/herm/skills.toml
                                           reconcile ~/.hermes/skills/herm/*
                                           restart gateway
  ◀── write-back resolved lockfile ───────┘
```

## Data model

### Lockfile `skills.toml`

```toml
[skills.debug]              # a skill shipped in this repo's skills/ (the catalog)
source  = "catalog"
enabled = true

[skills.pr-triage]          # external, pinned to a commit — the "lock"
source  = "git"
url     = "https://github.com/user/skills"
ref     = "a1b2c3d4e5f6..."  # full commit SHA, resolved at add-time
subdir  = "skills/pr-triage" # optional path within the repo
enabled = true

[skills.local-exp]          # authored on the laptop, vendored for reproducibility
source  = "local"
path    = "~/.config/herm/skills/local-exp"  # snapshot dir; pushed on sync
enabled = false
```

- `catalog` — resolves to `/opt/herm/skills/<name>/` (the repo payload on the VM).
- `git` — cloned at `ref` (a full commit SHA; branches/tags are resolved to a SHA at
  add-time so installs are reproducible and never silently float).
- `local` — at `add` time the directory is **vendored** into
  `~/.config/herm/skills/<name>/` on the laptop, so it survives `herm up --replace-vm`
  and is version-controllable. `path` records the snapshot location, not the volatile
  origin.
- `enabled` — toggles activation without uninstalling.

### Registry index (`registry.toml`)

A static file shipped in this repo (and overridable via
`[skills] registry = "<url-or-path>"` in `config.toml`). Maps a short name to a git
source:

```toml
[entries.pr-triage]
url         = "https://github.com/user/skills"
subdir      = "skills/pr-triage"
description = "Triage incoming PRs into draft reviews."
```

`herm skills add pr-triage` falls back to the registry when `pr-triage` is neither a
catalog skill, a local path, nor a URL.

### `requires:` frontmatter extension

A new **optional** field added to the SKILL.md frontmatter (alongside the existing
`name`, `description`, `tools`, `model`, `schedule`, `budget_usd`, `memory_scope`):

```yaml
requires:
  skills:   [other-skill]   # sibling skills — fetched transitively
  cli:      [gh, git]       # CLIs; also inferred from the existing `tools:` list
  mcp:      [linear]        # MCP servers — WARN only (owner must paste a token)
  toolsets: [slack]         # Hermes toolsets — WARN only (owner must enable)
```

Absent `requires:` ⇒ no declared deps (CLI deps are still inferred from `tools:`).

## Command surface

```
herm skills list                  # installed skills: source, enabled, dep status
herm skills add <name|path|url>   # resolve → fetch → install + deps → lock → reconcile
herm skills remove <name>         # uninstall, update lockfile, reconcile
herm skills enable  <name>        # toggle on  (no refetch)
herm skills disable <name>        # toggle off (no refetch)
herm skills info <name>           # frontmatter, resolved source, dep status, warnings
herm skills sync                  # reconcile VM to lockfile (also boot + `herm upgrade`)
```

`<name|path|url>` resolution order for `add`:
1. existing **catalog** skill name (`/opt/herm/skills/<name>`),
2. a **local** path that exists on the laptop (file/dir),
3. a **git URL** (`https://…`, `git@…`, `…#subdir`, `…@ref`),
4. a **registry** entry name,
5. otherwise error with the four tried interpretations.

## Dependency auto-resolve (on `add`)

1. Resolve source → fetch skill files into a staging area.
2. Parse frontmatter; collect `requires` and infer CLI deps from `tools:`
   (e.g. a `gh` tool ⇒ `gh` CLI).
3. **Sibling skills**: recursively `add` each `requires.skills` entry. Cycle-guarded
   (visited set) and deduplicated; siblings resolve through the same order above
   (catalog/registry/git).
4. **CLIs**: for each missing `requires.cli`/inferred CLI, install from the known fleet
   using the `10-install-cli-fleet.sh` package map (`claude`, `gh`, `gemini`, `codex`,
   `opencode`, …). Unknown CLIs ⇒ warn, continue.
5. **MCP servers / toolsets**: never auto-edited (they need owner tokens/config). Print
   an actionable warning (e.g. *"`pr-triage` needs the `linear` MCP — paste
   `LINEAR_API_KEY` in `~/.hermes/config.yaml`"* or *"needs toolset `slack` enabled in
   `config/hermes-tools.yaml`"*). The skill installs **flagged "degraded until
   configured."**
6. The lockfile is updated **only after** all skills are staged successfully (atomic:
   a failed fetch/parse leaves the lockfile unchanged). Then reconcile + restart
   gateway.

## Reconciliation semantics (`sync`)

`sync` makes the VM match the lockfile:

- **desired** = lockfile entries with `enabled = true`; **actual** = directories under
  `~/.hermes/skills/herm/`.
- Install missing, refresh changed (git `ref` mismatch), remove extras **only within
  the `herm/` namespace** (user-authored skills elsewhere untouched — preserves
  today's guarantee), and materialize `enabled` state.
- Idempotent. After changes, restart the gateway (`pkill -9 -f 'hermes gateway'`;
  systemd respawns).

## Boot integration & back-compat

- `cloud-init/scripts/07-seed-skills.sh` becomes a thin caller of `skillpm sync`.
- **No lockfile present** (existing deployments, first boot, or upgrade from the old
  seeder): seed the current six catalog skills enabled and write the initial lockfile.
  **Zero behavior change** for anyone running today.
- `herm upgrade` runs `skillpm sync` after pulling the latest catalog so catalog-pinned
  skills track the repo and git-pinned skills stay at their locked `ref`.

## Error handling

- Network/git failure on `add`: fail with a clear message; lockfile unchanged.
- Malformed frontmatter: reject with a parse error; do not install.
- Dependency cycle: detected and reported; abort the `add`.
- Missing MCP/toolset dep: warn, install anyway, mark "degraded."
- Partial `sync` failure: per-skill report, non-zero exit, successfully-synced skills
  left in place.

## Security considerations

Skills are **instructions executed by an autonomous agent that has tool access** — a
SKILL.md body becomes a system prompt and its `tools:` widen what a matching prompt can
do. Installing an external skill is therefore a supply-chain + prompt-injection surface.
Controls:

- **Tool-allowlist intersection (existing).** A skill's `tools:` is intersected with
  `config/hermes-tools.yaml`'s global allowlist; a skill can never grant itself a
  disabled toolset. This bounds blast radius regardless of source.
- **Pinned refs.** Git sources resolve to a full commit SHA at add-time. No floating
  branches ⇒ reproducible installs and no silent upstream updates.
- **Consent on external sources.** `add` from a git URL or registry prints the skill's
  `name`, `description`, `tools:`, and `requires:` and requires confirmation
  (`herm::confirm`) before install. `--yes` bypasses for automation.
- **No auto-enable of MCP/toolsets.** External skills can never cause a toolset to be
  enabled or a credential to be wired; those remain explicit owner actions.
- **Conservative defaults for foreign frontmatter.** External skills authored in the
  plain Anthropic Agent-Skills format (only `name` + `description`) get
  `tools: []` (most restrictive) unless the author specified otherwise; `herm skills
  info` shows the applied defaults so the owner can widen deliberately.

## Testing

- **Engine (`pytest`)**: source resolution (catalog/local/git/registry), frontmatter
  parse incl. foreign/minimal skills, dependency graph incl. cycle detection,
  reconcile diff (add/remove/refresh/toggle), lockfile round-trip. Fixtures: sample
  skill dirs + a local git fixture repo (no network).
- **Bash wrapper (`bats`)**: argument parsing, lockfile read/write helpers, and the
  `tailscale ssh` command construction (mock `tailscale`).
- **Back-compat**: a no-lockfile run seeds exactly the six catalog skills (matches
  today). Asserted as part of the boot-reconciler tests.

## Suggested implementation phases

The design is full-scope; implementation can land in reviewable slices:

1. **Backbone** — lockfile schema + `skillpm` reconcile + `07-seed-skills.sh` rewrite +
   back-compat; `herm skills list/enable/disable/sync`.
2. **Sources** — `add`/`remove` for catalog + local (vendoring) + git (pinned).
3. **Dependencies** — `requires:` parsing, transitive sibling resolution, fleet-CLI
   install, MCP/toolset warnings; consent prompt.
4. **Registry** — `registry.toml` + name resolution + `herm skills info`.

## Open questions

- Should `herm skills add <git-url>` support a private-repo auth path (reuse the VM's
  `gh` token), or document SSH-URL + deploy-key only? (Lean: document SSH for v1.)
- Lockfile location: dedicated `~/.config/herm/skills.toml` (chosen) vs a `[skills]`
  table inside `config.toml`. Separate file keeps the hand-rolled TOML reader simple
  and the lockfile diff-friendly.
