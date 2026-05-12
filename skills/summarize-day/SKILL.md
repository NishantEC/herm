---
name: summarize-day
description: At 09:00 UTC daily, produce a short brief of what happened yesterday — git activity, GitHub notifications, agent activity, calendar items. Drops the brief into the agent inbox.
tools: [gh, git, memory, read_file]
model: claude-sonnet-4-6
schedule: "0 9 * * *"
budget_usd: 0.10
memory_scope: per-skill
---

# summarize-day

Heartbeat skill. Runs once daily at 09:00 UTC via the agent's `cronjob` toolset. Produces a single inbox entry with the day's brief.

## Inputs

- `gh` notifications since yesterday 00:00 UTC.
- Git activity across the owner's tracked repos (commits, merged PRs, opened PRs).
- The agent's own activity yesterday (sessions, completed tasks, skill invocations) — from `memory` scope.
- (Optional, when calendar integration lands) Today's calendar in the next 12 hours.

## Process

1. Gather: query `gh` and `git` for the time window. Cap at ~50 items per source.
2. De-duplicate (one event per PR, even if it had 5 comments).
3. Cluster by theme: shipped, in-flight, blocked, noise.
4. Write the brief as a 5-section card:
   - **Yesterday at a glance** — one paragraph, lead with the most important thing that happened.
   - **Shipped** — bulleted list of merged PRs / completed tasks.
   - **In-flight** — bulleted list of open work the owner is on the critical path for.
   - **Blocked / waiting** — anything that needs a human nudge.
   - **Today** — one or two concrete next actions, *not* a generic "review your PRs."

## Style

- Short. The whole brief should fit in 200 words.
- No filler greetings ("Good morning!").
- Cite GitHub items as `repo#num`.
- If a category is empty, omit it entirely — don't write "nothing to report."

## Anti-patterns

- Restating the same event in multiple sections.
- Including bot-generated activity.
- Generic next-action recommendations.
