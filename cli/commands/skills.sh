# shellcheck shell=bash
# herm skills — manage the agent's skill set on the VM via the skillpm engine.
# Thin wrapper: transports subcommands to /opt/herm/skillpm over Tailscale SSH.

herm::__skills_run() {
  local hostname
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"
  herm::require_cmd tailscale
  tailscale ssh "herm@$hostname" -- \
    env PYTHONPATH=/opt/herm SKILLPM_CATALOG=/opt/herm/skills \
    /home/herm/.hermes/hermes-agent/venv/bin/python -m skillpm "$@"
}

herm::cmd::skills() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH — run 'herm init' first"
  fi
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list|sync)
      herm::__skills_run "$sub"
      ;;
    enable|disable)
      [[ -n ${1:-} ]] || herm::die "usage: herm skills $sub <name>"
      herm::__skills_run "$sub" "$1"
      ;;
    help|-h|--help)
      cat <<'EOF'
usage: herm skills <subcommand>

  list                 show installed skills and enabled/live state
  sync                 reconcile the VM's skill set to the lockfile
  enable <name>        enable a skill and reconcile
  disable <name>       disable a skill and reconcile
EOF
      ;;
    *)
      herm::die "unknown subcommand: $sub (try: herm skills help)"
      ;;
  esac
}
