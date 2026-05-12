---
name: debug
description: Given an error message, stack trace, or unexpected behavior, narrow down the cause and propose a minimal fix. Pulls in repo context, reads logs, suggests instrumentation.
tools: [read_file, write_file, bash, ripgrep, web_fetch]
model: claude-sonnet-4-6
schedule: ""
budget_usd: 0.50
memory_scope: per-skill
---

# debug

Use this skill when the user pastes an error, stack trace, failing test, or describes "something is broken." Goal: a single concrete fix the user can apply, with a one-line justification.

## Process

1. **Reproduce in your head.** Restate the failure mode in 1–2 sentences. If you can't, ask one clarifying question (don't guess).
2. **Locate the relevant code.** Use `ripgrep` on the active repo to find the function/file mentioned in the trace. If the trace is from a third-party lib, read its public interface first via `read_file` or `web_fetch`.
3. **Form a hypothesis.** One concrete cause. Don't list five "could be"s — pick the most likely and act on it.
4. **Verify the hypothesis.** Add instrumentation (print/log/assert) or read the failing test more carefully. Only then claim the cause.
5. **Propose the minimal fix.** Single diff, single rationale. If there are two plausible fixes, pick one and say "the other would be X if Y."
6. **Write a regression test** if the codebase has tests. Failing test first, then the fix.

## Anti-patterns

- "It might be A or B or C" — pick one.
- Patching the symptom instead of the cause. If you find yourself adding a try/except that swallows the original error, stop and find the real cause.
- Rewriting unrelated code. Stay surgical.

## Output shape

```
Cause: <one sentence>
Evidence: <how you confirmed it>
Fix: <diff or specific instruction>
Test: <how to verify the fix>
```
