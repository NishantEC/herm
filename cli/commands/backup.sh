# shellcheck shell=bash
# herm backup — force-trigger the GCS rsync that herm-backup.timer normally
# runs nightly. Useful before risky operations or before stepping away.

herm::cmd::backup() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local subcmd="${1:-now}"
  case "$subcmd" in
    now)
      ;;
    list)
      herm::__backup_list
      return
      ;;
    *)
      cat <<EOF >&2
usage: herm backup [now|list]

  now     trigger an immediate rsync (default)
  list    list dated backup folders in the GCS bucket
EOF
      return 2
      ;;
  esac

  herm::require_cmd gcloud

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  herm::log "triggering immediate backup on $hostname..."
  gcloud compute ssh "$hostname" \
    --project "$project_id" \
    --zone "$zone" \
    --tunnel-through-iap \
    --command "sudo systemctl start herm-backup.service"

  herm::log "backup unit started; check status with 'herm logs herm-backup'"
}

herm::__backup_list() {
  herm::require_cmd gsutil
  local project_id
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  gsutil ls "gs://${project_id}-herm-backups/" 2>/dev/null \
    || herm::err "could not list gs://${project_id}-herm-backups/"
}
