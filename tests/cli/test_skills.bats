setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(mktemp -d)"
  mkdir -p "$TMP/cfg"
  printf '[tailscale]\nhostname = "herm-vm"\n' > "$TMP/cfg/config.toml"
  export HERM_CONFIG_PATH="$TMP/cfg/config.toml"
  # Stub tailscale: log every invocation, drain any piped stdin (the deploy
  # streams a tar) so the producing pipeline doesn't see EPIPE.
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/tailscale" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/ts.log"
cat >/dev/null 2>&1 || true
exit 0
EOF
  chmod +x "$TMP/bin/tailscale"
  export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "herm skills list deploys engine then runs list" {
  run "$REPO/bin/herm" skills list
  [ "$status" -eq 0 ]
  grep -q 'tar xzf - -C /home/herm/.hermes/skillpm' "$TMP/ts.log"   # engine pushed
  grep -q 'tar xzf - -C /home/herm/.hermes/skill-catalog' "$TMP/ts.log"  # catalog pushed
  grep -q -- '-m skillpm list' "$TMP/ts.log"
}

@test "herm skills sync reconciles with --reload" {
  run "$REPO/bin/herm" skills sync
  [ "$status" -eq 0 ]
  grep -q -- '-m skillpm sync --reload' "$TMP/ts.log"
}

@test "herm skills enable requires a name" {
  run "$REPO/bin/herm" skills enable
  [ "$status" -ne 0 ]
}

@test "herm skills enable passes the name and --reload" {
  run "$REPO/bin/herm" skills enable debug
  [ "$status" -eq 0 ]
  grep -q -- '-m skillpm enable debug --reload' "$TMP/ts.log"
}

@test "herm skills deploy pushes engine and catalog" {
  run "$REPO/bin/herm" skills deploy
  [ "$status" -eq 0 ]
  grep -q '/home/herm/.hermes/skillpm' "$TMP/ts.log"
  grep -q '/home/herm/.hermes/skill-catalog' "$TMP/ts.log"
}

@test "herm skills rejects unknown subcommand" {
  run "$REPO/bin/herm" skills frobnicate
  [ "$status" -ne 0 ]
}
