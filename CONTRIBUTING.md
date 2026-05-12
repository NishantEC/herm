# Contributing to herm

Thanks for considering a contribution. `herm` is early; expect the design to move.

## Before opening a PR

1. Run `make check` locally. CI runs the same checks.
2. If you're changing `terraform/`, run `terraform fmt`, `terraform validate`, and `tflint`.
3. If you're changing bash, run `shellcheck` on the affected files.
4. If you're changing user-facing behavior, update `CHANGELOG.md` under `## [Unreleased]`.

## Branching

- `main` is what stable releases come from.
- Open PRs against `main` from a feature branch.

## Commit messages

Conventional Commits style (`feat:`, `fix:`, `docs:`, `chore:`). Keep the first line under 72 chars.

## Cost & risk

Many changes here can cost real GCP money if they're wrong. PRs that touch Terraform should either:
- Include `terraform plan` output in the description, or
- Note explicitly that the change is plan-only with no `apply` impact.

## Code of Conduct

By participating you agree to the [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).
