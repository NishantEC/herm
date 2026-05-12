# shellcheck shell=bash
# herm qr — print a terminal QR code containing the Hermes gateway URL +
# bearer token, formatted for one-tap setup on a phone HTTP client.

herm::cmd::qr() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  herm::require_cmd qrencode || {
    herm::err "qrencode is not installed locally."
    herm::err "Install it (macOS):  brew install qrencode"
    herm::err "             (Linux):  apt-get install qrencode"
    return 1
  }

  herm::require_cmd gcloud

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  # Pull the bearer token off the VM via IAP SSH.
  herm::log "fetching bearer token from $hostname..."
  local token
  token=$(gcloud compute ssh "$hostname" \
    --project "$project_id" \
    --zone "$zone" \
    --tunnel-through-iap \
    --command "sudo -u herm cat /home/herm/.hermes/.api-token" 2>/dev/null | tr -d '\r\n')

  if [[ -z $token ]]; then
    herm::die "failed to fetch bearer token from VM"
  fi

  local url="http://$hostname:8642/v1"
  local payload="herm://$hostname:8642?token=$token"

  echo
  echo "Hermes gateway:  $url"
  echo "Bearer token:    $token"
  echo
  echo "QR (scan from phone HTTP client app that understands herm:// URIs)"
  echo
  qrencode -t ANSIUTF8 -- "$payload"
  echo
  echo "Or scan this URL-only QR (then paste the token manually):"
  echo
  qrencode -t ANSIUTF8 -- "$url"
}
