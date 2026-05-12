# shellcheck shell=bash
# herm console — open the GCP console page for this VM in the default browser.

herm::cmd::console() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  local url="https://console.cloud.google.com/compute/instancesDetail/zones/${zone}/instances/${hostname}?project=${project_id}"

  if command -v open >/dev/null 2>&1; then
    open "$url"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  else
    herm::log "no open/xdg-open found; URL:"
    echo "$url"
  fi
}
