# shellcheck shell=bash
# herm ssh — tailscale ssh herm@<hostname>.

herm::cmd::ssh() {
  herm::require_cmd tailscale

  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local hostname
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  herm::log "connecting via Tailscale SSH..."
  exec tailscale ssh "herm@$hostname"
}
