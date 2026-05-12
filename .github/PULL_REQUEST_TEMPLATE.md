## What

<!-- One paragraph: what changed and why. -->

## Cost & security impact

- [ ] No Terraform changes
- [ ] Terraform changes — `terraform plan` output included below (or "plan-only, no apply impact")
- [ ] No new secrets, IAM bindings, or firewall rules
- [ ] No new outbound destinations added to v0.4 NAT allowlist (when applicable)

<details>
<summary>terraform plan</summary>

```
<paste plan here>
```
</details>

## Testing

- [ ] `make check` passes locally
- [ ] Manual integration test against a throwaway GCP project (if applicable; note cost)

## Docs

- [ ] CHANGELOG.md updated under `## [Unreleased]`
- [ ] User-facing docs updated (README / docs/) if behavior changed
