#!/usr/bin/env bats

setup() {
  HERM_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  load "$HERM_REPO_ROOT/cli/lib.sh"
  # shellcheck source=../../cli/commands/up.sh
  source "$HERM_REPO_ROOT/cli/commands/up.sh"
}

@test "render_cloud_init inlines all base64 placeholders" {
  rendered="$(herm::__render_cloud_init)"
  ! grep -q 'BASE64_01' <<<"$rendered"
  ! grep -q 'BASE64_02' <<<"$rendered"
  ! grep -q 'BASE64_03' <<<"$rendered"
  ! grep -q 'BASE64_04' <<<"$rendered"
  ! grep -q 'BASE64_05' <<<"$rendered"
  ! grep -q 'BASE64_99' <<<"$rendered"
  ! grep -q 'BASE64_UNIT_HERMES' <<<"$rendered"
  ! grep -q 'BASE64_UNIT_BACKUP_SVC' <<<"$rendered"
  ! grep -q 'BASE64_UNIT_BACKUP_TIMER' <<<"$rendered"
}

@test "render_cloud_init produces valid YAML preamble" {
  rendered="$(herm::__render_cloud_init)"
  [[ "${rendered:0:13}" == "#cloud-config" ]]
}

@test "render_cloud_init encoded blocks decode back to the source files" {
  rendered="$(herm::__render_cloud_init)"
  # Pull out the 01-mount-disk encoded value and decode it.
  encoded="$(grep -A3 '01-mount-disk' <<<"$rendered" | grep -o 'content: .*' | tr -d '\n' | sed 's/^content: //')"
  decoded="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)"
  [[ "$decoded" == *"format \$DEVICE as ext4"* || "$decoded" == *"formatting"* ]]
}
