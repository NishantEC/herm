#!/usr/bin/env bats

setup() {
  HERM_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  load "$HERM_REPO_ROOT/cli/lib.sh"
  # shellcheck source=../../cli/commands/up.sh
  source "$HERM_REPO_ROOT/cli/commands/up.sh"
}

@test "render_startup_script begins with #!/bin/bash" {
  rendered="$(herm::__render_startup_script)"
  [[ "${rendered:0:11}" == "#!/bin/bash" ]]
}

@test "render_startup_script inlines every per-step script" {
  rendered="$(herm::__render_startup_script)"
  grep -q '/opt/herm/scripts/01-mount-disk.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/02-create-user.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/03-install-base.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/04-install-hermes.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/05-tailscale-join.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/07-seed-skills.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/08-tool-allowlist.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/09-install-reaper.sh <<' <<<"$rendered"
  grep -q '/opt/herm/scripts/99-systemd-units.sh <<' <<<"$rendered"
}

@test "render_startup_script inlines every systemd unit" {
  rendered="$(herm::__render_startup_script)"
  grep -q '/etc/systemd/system/hermes-agent.service <<' <<<"$rendered"
  grep -q '/etc/systemd/system/herm-backup.service <<' <<<"$rendered"
  grep -q '/etc/systemd/system/herm-backup.timer <<' <<<"$rendered"
  grep -q '/etc/systemd/system/herm-reaper.service <<' <<<"$rendered"
  grep -q '/etc/systemd/system/herm-reaper.timer <<' <<<"$rendered"
}

@test "render_startup_script inlines hermes tool-disable policy" {
  rendered="$(herm::__render_startup_script)"
  grep -q '/opt/herm/config/hermes-tools.yaml <<' <<<"$rendered"
  grep -Fq 'disabled_toolsets:' <<<"$rendered"
  grep -Fq 'computer_use' <<<"$rendered"
  # slack is intentionally not in the disabled list anymore — it's enabled
  # via Socket Mode when SLACK_BOT_TOKEN/SLACK_APP_TOKEN are present.
  ! grep -E '^\s+- slack$' <<<"$rendered"
}

@test "render_startup_script inlines every shipped skill SKILL.md" {
  rendered="$(herm::__render_startup_script)"
  for skill in debug review-pr write-doc update-deps watch-repo summarize-day; do
    grep -q "/opt/herm/skills/$skill/SKILL.md" <<<"$rendered" \
      || (echo "missing skill: $skill" && false)
  done
}

@test "render_startup_script declares HERM_REAPER_ENABLED" {
  rendered="$(herm::__render_startup_script)"
  grep -Eq 'export HERM_REAPER_ENABLED=[01]' <<<"$rendered"
}

@test "render_startup_script preserves literal \$VAR refs in inlined script bodies" {
  # Each per-step script uses bash vars like $DEVICE, $HOSTNAME. The outer
  # heredoc is single-quoted so they must survive verbatim.
  rendered="$(herm::__render_startup_script)"
  grep -Fq 'DEVICE="/dev/disk/by-id/google-herm-data"' <<<"$rendered"
  grep -Fq 'HOSTNAME=$(hostname)' <<<"$rendered"
}

@test "render_startup_script ends by invoking all step scripts in order" {
  rendered="$(herm::__render_startup_script)"
  # Capture only the tail after the last heredoc close. v0.2 has two kinds
  # of heredoc closer (__HERM_FILE__ and __HERM_SKILL_FILE__) since skills
  # got their own delimiter to avoid collisions with potential `__HERM_FILE__`
  # inside skill markdown.
  tail_line="$(awk '/^(__HERM_FILE__|__HERM_SKILL_FILE__)$/{found=NR} END{print found}' <<<"$rendered")"
  [[ -n "$tail_line" ]]
  invocation_block="$(tail -n +"$tail_line" <<<"$rendered")"
  grep -q '/opt/herm/scripts/01-mount-disk.sh$' <<<"$invocation_block"
  grep -q '/opt/herm/scripts/05-tailscale-join.sh$' <<<"$invocation_block"
  grep -q '/opt/herm/scripts/07-seed-skills.sh$' <<<"$invocation_block"
  grep -q '/opt/herm/scripts/08-tool-allowlist.sh$' <<<"$invocation_block"
  grep -q '/opt/herm/scripts/09-install-reaper.sh$' <<<"$invocation_block"
  grep -q '/opt/herm/scripts/99-systemd-units.sh$' <<<"$invocation_block"
}
