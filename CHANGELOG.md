# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial design spec (`docs/superpowers/specs/2026-05-13-herm-design.md`).
- v0.1 foundation: Terraform-provisioned GCP VM, Tailscale tunnel, persistent disk, GCS backup, hardened systemd unit for Hermes Agent.
- `herm` CLI with `init`, `up`, `down`, `nuke`, `status`, `ssh` subcommands.
- CI: shellcheck, terraform fmt/validate/tflint, trivy, gitleaks, markdownlint.

[Unreleased]: https://github.com/NishantEC/herm/commits/main
