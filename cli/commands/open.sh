# shellcheck shell=bash
# herm open — open one of the VM's surfaces in the default browser.
# Tailscale must be running on the laptop for the URL to resolve.

herm::cmd::open() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local hostname
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  local target="${1:-hermes}"
  local url=""
  case "$target" in
    hermes|gateway)
      url="http://$hostname:8642/v1/models"
      ;;
    health)
      url="http://$hostname:8642/health"
      ;;
    console)
      # GCP console for the VM.
      local project_id zone
      project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
      zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
      url="https://console.cloud.google.com/compute/instancesDetail/zones/$zone/instances/$hostname?project=$project_id"
      ;;
    tailscale)
      url="https://login.tailscale.com/admin/machines"
      ;;
    *)
      cat <<EOF >&2
usage: herm open [target]

targets:
  hermes    Hermes gateway /v1/models (default)
  health    Hermes /health endpoint
  console   This VM in the GCP console
  tailscale Tailscale admin machines list

EOF
      return 2
      ;;
  esac

  # macOS uses 'open', Linux uses 'xdg-open'.
  if command -v open >/dev/null 2>&1; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  else
    herm::log "no open/xdg-open found; here's the URL: $url"
  fi
}
