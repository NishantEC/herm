# Skills

`herm` ships 6 skills in v0.2 and seeds them into Hermes Agent at boot. Skills tell the agent how to handle specific kinds of requests — `debug` for stack traces, `review-pr` for PR URLs, etc. Hermes auto-discovers them from `~/.hermes/skills/herm/` and matches incoming prompts against their `description:` frontmatter.

## What's shipped

| Skill | When it fires | Tools it can use |
|---|---|---|
| `debug` | Errors, stack traces, "something is broken" | read/write files, bash, ripgrep, web fetch |
| `review-pr` | PR URL or "review PR X" | `gh`, read files, web fetch |
| `write-doc` | "write a doc," "explain in README" | read/write files (only under `docs/`) |
| `update-deps` | "bump deps," "upgrade X" | bash, git, gh, web fetch |
| `watch-repo` | Every 30 min via cron | `gh`, memory |
| `summarize-day` | Daily at 09:00 UTC via cron | `gh`, git, memory |

The two cron-scheduled skills (`watch-repo`, `summarize-day`) run on Hermes' built-in `cronjob` scheduler without owner interaction once they're seeded.

## SKILL.md format

Each skill is a directory containing a `SKILL.md` file:

```markdown
---
name: <unique-name>
description: One-sentence summary Hermes uses for prompt matching.
tools: [comma, separated, tool, names]
model: claude-sonnet-4-6
schedule: ""                  # empty = on-demand. cron string = heartbeat.
budget_usd: 0.10
memory_scope: per-skill       # or per-project, or global
---

# <skill name>

Instructions to the agent, written in Markdown.

## Sub-headers

Anything below the frontmatter is the skill's "system prompt." Use it to
specify process, anti-patterns, output shape, etc.
```

The `tools:` list is the *intersection* with Hermes' global tool allowlist (`config/hermes-tools.yaml`). A skill cannot grant itself access to a tool the gateway disabled.

## Adding your own skill

On the VM (via `tailscale ssh herm@herm-vm`):

```bash
mkdir -p ~/.hermes/skills/herm/my-skill
cat > ~/.hermes/skills/herm/my-skill/SKILL.md <<'EOF'
---
name: my-skill
description: ...
tools: [read_file]
model: claude-sonnet-4-6
---
# my-skill

...
EOF
pkill -9 -f 'hermes gateway'   # systemd respawns; skill auto-discovers
```

User-authored skills under `~/.hermes/skills/<not-herm>/` are preserved across `herm up`/`herm down` cycles because they live on the persistent disk. The `herm/` subdirectory is reserved for skills shipped by this repo and gets `rsync --delete`'d on each `herm upgrade`.

## Cron skills

A skill with a non-empty `schedule:` value registers with Hermes' `cronjob` toolset on startup. The cron syntax is standard 5-field (`min hour day month weekday`). Outputs go into the agent's inbox session, not the active TUI session.

Disable a cron skill by setting `schedule: ""` and rerunning `herm upgrade`.

## Budgets

`budget_usd:` is a per-invocation ceiling. Hermes computes a running estimate from token usage and aborts the skill mid-run if it crosses the cap. The estimate is provider-priced, so set the cap against the model you've pinned in `model:`.

## Anti-patterns when authoring skills

- **Over-broad `tools:` lists.** Every tool you add widens the blast radius of a prompt-injected skill invocation. Start with the minimum.
- **Vague `description:` lines.** Hermes matches incoming prompts against descriptions; a fuzzy one means the wrong skill fires.
- **Long preambles.** The `SKILL.md` body becomes a system prompt — keep it terse, process-focused, not background-heavy.
- **Hard-coding paths.** Skills run as `herm` on the VM. Use `$HOME`, not `/home/herm`.
