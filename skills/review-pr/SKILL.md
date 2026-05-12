---
name: review-pr
description: Review a GitHub PR — read the diff, the linked issue if any, and the changed-file context, then write a single structured review comment that leads with the highest-impact concern.
tools: [gh, read_file, web_fetch]
model: claude-sonnet-4-6
schedule: ""
budget_usd: 0.30
memory_scope: per-skill
---

# review-pr

Use when the user pastes a PR URL or says "review PR X." Output a single coherent comment, not line-by-line nitpicks.

## Process

1. `gh pr view <url> --json title,body,baseRefName,headRefName,changedFiles,additions,deletions,author,labels` for metadata.
2. `gh pr diff <url>` for the diff. If >2k lines, skim and call out which files you focused on.
3. If the PR body links an issue (#NNN), read it via `gh issue view`. Anchor the review against the issue's stated problem.
4. For each changed file, ask: does the change accomplish what the title/body claim? Does it introduce risk the author didn't mention?
5. Identify the **one** highest-impact concern. Could be a correctness bug, a security regression, a breaking change in a public API, a missing test, or a design smell. Just one.
6. Optionally list up to 3 minor notes (style, naming, docs).

## Style

- Lead with the highest-impact concern in the first sentence. No throat-clearing.
- Cite specific `file:line` locations.
- Affirm what's well done in one line at the end. (Real affirmation, not praise theater.)
- Never paste back the diff to the author.
- If the PR is clean and ready to merge, say so plainly: "Looks good to ship. No blockers."

## Output

Submit via `gh pr review <url> --comment --body <body>`. Don't approve or request-changes; let the human decide.

## Anti-patterns

- Demanding tests for code that doesn't have testable behavior (config changes, doc updates).
- Bike-shedding naming when the surrounding code uses the proposed name's antonym.
- Suggesting refactors unrelated to the PR's scope.
