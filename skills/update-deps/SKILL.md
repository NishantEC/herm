---
name: update-deps
description: Open a PR upgrading dependencies in a git worktree. Never commits to main directly. Surfaces breaking changes per dependency by reading the upstream changelog.
tools: [bash, gh, git, read_file, write_file, web_fetch]
model: claude-sonnet-4-6
schedule: ""
budget_usd: 0.40
memory_scope: per-skill
---

# update-deps

Use when the user asks "bump dependencies," "update X to latest," or "what would breaking changes look like if I upgrade Y." Output is a draft PR with a structured body explaining each bump.

## Process

1. Detect the package manager from lockfile: `package.json` + `package-lock.json`/`pnpm-lock.yaml`/`yarn.lock`, `Cargo.toml`, `pyproject.toml`/`requirements*.txt`, `go.mod`, `Gemfile`. If unclear, list candidates and ask.
2. Create a worktree: `git worktree add ../<repo>-deps update-deps-<date>`.
3. Per dependency the user wants bumped (or all if "all"):
   a. Identify current version.
   b. Identify target version (`npm view`, `cargo info`, etc.).
   c. Read the upstream changelog (web_fetch) between current and target. Note breaking changes.
   d. Apply the bump via the package manager's lockfile-updating command (no manual editing of lockfiles).
4. Run the test suite if there is one. Capture failures.
5. Open a draft PR with body:
   - One section per bumped dep.
   - Old → new version.
   - Breaking changes called out as ⚠️ with link to the changelog entry.
   - Test outcome (pass / fail / N/A).
6. Print the PR URL.

## Safety

- Never push to `main` directly. Always a feature branch + draft PR.
- Never auto-merge.
- If a bump introduces a CVE-fix, call it out at the top of the PR body.

## Anti-patterns

- Bumping major versions silently because "latest is greatest." Flag every major.
- Squashing the changelog into a one-liner.
- Mass-bumping without listing breaking changes per dep.
