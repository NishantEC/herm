setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(mktemp -d)"
  # Fake config so herm::read_config finds a hostname.
  mkdir -p "$TMP/cfg"
  printf '[tailscale]\nhostname = "herm-vm"\n' > "$TMP/cfg/config.toml"
  export HERM_CONFIG_PATH="$TMP/cfg/config.toml"
  # Stub tailscale: record the args it was called with.
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/tailscale" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$TMP/tailscale.args"
EOF
  chmod +x "$TMP/bin/tailscale"
  export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "herm skills list invokes skillpm list over tailscale ssh" {
  run "$REPO/bin/herm" skills list
  [ "$status" -eq 0 ]
  grep -q 'ssh herm@herm-vm' "$TMP/tailscale.args"
  grep -q -- '-m skillpm list' "$TMP/tailscale.args"
}

@test "herm skills enable requires a name" {
  run "$REPO/bin/herm" skills enable
  [ "$status" -ne 0 ]
}

@test "herm skills rejects unknown subcommand" {
  run "$REPO/bin/herm" skills frobnicate
  [ "$status" -ne 0 ]
}
