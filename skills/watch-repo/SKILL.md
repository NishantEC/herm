---
name: watch-repo
description: Poll a GitHub repo every 30 minutes for events the owner cares about — new PR comments, failing CI, merge-ready PRs, security alerts. Drop a one-line note in the agent inbox for each.
tools: [gh, web_fetch, memory]
model: claude-sonnet-4-6
schedule: "*/30 * * * *"
budget_usd: 0.05
memory_scope: per-skill
---

# watch-repo

Heartbeat skill. Runs every 30 minutes via the agent's `cronjob` toolset. Reads recent activity on the repo(s) the owner has registered, emits notes to the agent inbox.

## State

Per-repo "last seen" event ID stored under `memory_scope: per-skill`. On each run, fetch events since the last seen, then update.

## What to flag

- A new comment on a PR the owner authored or is assigned to.
- A CI run on the owner's PR that just turned red.
- A PR that's gone from "draft" to "ready for review" if the owner is a reviewer.
- A new Dependabot or security alert.
- A new release on a repo the owner is watching with the `subscribe` flag set.

## What to ignore

- Robot comments on the owner's own PRs (Vercel previews, CodeRabbit, etc.).
- Notifications about repos the owner doesn't actively work in.
- "Welcome new contributor" templates.

## Output shape per event

```
[<repo>#<num>] <one-sentence note>  →  <url>
```

Bundled into a single inbox entry per heartbeat, not one per event (avoid notification fatigue).

## Anti-patterns

- Flagging every CI green run.
- Re-flagging the same event because state wasn't persisted.
- Long-winded summaries; one line per event.
