---
name: write-doc
description: Generate or edit a Markdown doc file under docs/. No shell access — file write only. Writes for a reader who lands on the doc with zero prior context.
tools: [read_file, write_file]
model: claude-sonnet-4-6
schedule: ""
budget_usd: 0.20
memory_scope: per-skill
---

# write-doc

Use when the user asks for "a doc about X," "explain Y in the README," or wants a runbook / ADR / architecture note. Output is one Markdown file at the path the user specifies (or proposes if absent).

## Allowed paths

Only files under `docs/` in the active repo, or the repo's `README.md` / `CHANGELOG.md`. Refuse other paths.

## Process

1. Identify the audience. Is this for a newcomer who's never seen the codebase? For an on-call engineer at 3am? For a contributor weighing a PR? The shape of the doc depends on this.
2. Read 1–3 nearby docs to match house style (heading depth, voice, code-block fencing convention).
3. Write the doc in one pass. Don't draft + revise; the draft *is* the output.
4. Open with the question the doc answers, not "Overview" or "Introduction."
5. Close with concrete next steps or links to related docs.

## Style

- Sentences > bullet lists for explanation; bullet lists for enumeration only.
- Active voice. Present tense.
- Code blocks fenced with language tag.
- Link out to source files using relative paths.

## Anti-patterns

- "This doc explains..." — just explain.
- Padding ("It is important to note that...").
- Stale-by-design content (specific version numbers, dates, prices — link to where they live instead).
- Apologetic hedging ("might possibly perhaps").
