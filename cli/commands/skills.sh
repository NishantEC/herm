# shellcheck shell=bash
# herm skills — manage the agent's skill set on the VM via the skillpm engine.
#
# The engine + catalog are herm-owned (~/.hermes/, on the persistent disk) and
# self-deployed from this repo over Tailscale SSH as the `herm` user — no root,
# no reprovision. Mutating commands reload the gateway so changes take effect.

HERM_SKILLPM_REMOTE=/home/herm/.hermes/skillpm
HERM_CATALOG_REMOTE=/home/herm/.hermes/skill-catalog
HERM_VENV_PY=/home/herm/.hermes/hermes-agent/venv/bin/python

# Push one local dir's CONTENTS to a remote dir via a tar stream over Tailscale
# SSH (clean replace; no rsync/scp dependency, no root).
herm::__skills_push() {
  local host="$1" src="$2" dest="$3"
  tar czf - -C "$src" --exclude='__pycache__' --exclude='.DS_Store' . \
    | tailscale ssh "herm@$host" -- \
        "rm -rf $dest && mkdir -p $dest && tar xzf - -C $dest"
}

herm::__skills_deploy() {
  local host="$1"
  herm::log "deploying engine + catalog to $host (herm-owned, no root)…"
  herm::__skills_push "$host" "$HERM_REPO_ROOT/skillpm" "$HERM_SKILLPM_REMOTE"
  herm::__skills_push "$host" "$HERM_REPO_ROOT/skills" "$HERM_CATALOG_REMOTE"
}

herm::__skills_run() {
  local host="$1"
  shift
  tailscale ssh "herm@$host" -- \
    env PYTHONPATH=/home/herm/.hermes "$HERM_VENV_PY" -m skillpm "$@" </dev/null
}

herm::cmd::skills() {
  [[ -f $HERM_CONFIG_PATH ]] || herm::die "no config at $HERM_CONFIG_PATH — run 'herm init' first"
  herm::require_cmd tailscale
  local host
  host="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  local sub="${1:-list}"
  shift || true
  case "$sub" in
    deploy)
      herm::__skills_deploy "$host"
      herm::log "deployed."
      ;;
    list)
      herm::__skills_deploy "$host"
      herm::__skills_run "$host" list
      ;;
    sync)
      herm::__skills_deploy "$host"
      herm::__skills_run "$host" sync --reload
      ;;
    enable|disable)
      [[ -n ${1:-} ]] || herm::die "usage: herm skills $sub <name>"
      herm::__skills_deploy "$host"
      herm::__skills_run "$host" "$sub" "$1" --reload
      ;;
    help|-h|--help)
      cat <<'EOF'
usage: herm skills <subcommand>

  list                 deploy the engine, then show installed skills + state
  sync                 reconcile the VM to the lockfile and reload the gateway
  enable <name>        enable a skill, reconcile, reload the gateway
  disable <name>       disable a skill, reconcile, reload the gateway
  deploy               push the engine + catalog to the VM (herm-owned, no root)

The engine and catalog are pushed from this repo on every command, so the VM
always runs the current code. State (lockfile, live skills) lives on the
persistent disk and survives rebuilds.
EOF
      ;;
    *)
      herm::die "unknown subcommand: $sub (try: herm skills help)"
      ;;
  esac
}
