# shellcheck shell=bash
# herm logs <unit> — tail journald for a systemd unit on the VM.
# Uses gcloud IAP SSH so sudo journalctl works.

herm::cmd::logs() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local unit="${1:-hermes-agent}"
  local lines="${2:-100}"

  herm::require_cmd gcloud

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  # Known units we proxy:
  case "$unit" in
    hermes-agent|herm-backup|herm-backup.timer|herm-reaper|herm-reaper.timer|tailscaled|google-startup-scripts)
      ;;
    *)
      herm::warn "unknown unit '$unit' — passing through to journalctl anyway"
      ;;
  esac

  herm::log "tailing $unit on $hostname (Ctrl-C to stop)..."
  gcloud compute ssh "$hostname" \
    --project "$project_id" \
    --zone "$zone" \
    --tunnel-through-iap \
    -- -t "sudo journalctl -u $unit -n $lines -f --no-pager"
}
