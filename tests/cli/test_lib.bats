#!/usr/bin/env bats

setup() {
  HERM_REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  load "$HERM_REPO_ROOT/cli/lib.sh"
}

@test "herm::require_cmd succeeds for existing command" {
  run herm::require_cmd bash
  [ "$status" -eq 0 ]
}

@test "herm::require_cmd fails for missing command" {
  run herm::require_cmd definitely-not-a-real-command-xyz
  [ "$status" -ne 0 ]
  [[ "$output" == *"definitely-not-a-real-command-xyz"* ]]
}

@test "herm::read_config returns project_id from fixture" {
  result="$(herm::read_config "$HERM_REPO_ROOT/tests/fixtures/config.toml" gcp project_id)"
  [ "$result" = "fixture-project" ]
}

@test "herm::read_config returns numeric value" {
  result="$(herm::read_config "$HERM_REPO_ROOT/tests/fixtures/config.toml" budget monthly_usd)"
  [ "$result" = "25" ]
}

@test "herm::read_config errors on missing key" {
  run herm::read_config "$HERM_REPO_ROOT/tests/fixtures/config.toml" gcp nonexistent
  [ "$status" -ne 0 ]
}
