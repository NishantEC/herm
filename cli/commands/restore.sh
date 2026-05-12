# shellcheck shell=bash
# herm restore — restore /home/herm from a dated GCS backup folder.
# Stops Hermes, rsyncs the backup over /home/herm, restarts.
# Destructive on the VM's /home/herm — confirms before proceeding.

herm::cmd::restore() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local timestamp="${1:-}"
  if [[ -z $timestamp ]]; then
    cat <<EOF >&2
usage: herm restore <YYYY-MM-DD>

list available dated backup folders with 'herm backup list'.
EOF
    return 2
  fi

  herm::require_cmd gcloud
  herm::require_cmd gsutil

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  local backup_path="gs://${project_id}-herm-backups/${timestamp}/"
  if ! gsutil ls "$backup_path" >/dev/null 2>&1; then
    herm::die "backup folder not found: $backup_path"
  fi

  herm::warn "this will OVERWRITE /home/herm on $hostname with the contents of:"
  herm::warn "  $backup_path"
  if ! herm::confirm "Continue?"; then
    herm::log "aborted"
    return 0
  fi

  herm::log "stopping hermes-agent on $hostname..."
  gcloud compute ssh "$hostname" \
    --project "$project_id" --zone "$zone" --tunnel-through-iap \
    --command "sudo systemctl stop hermes-agent"

  herm::log "restoring from $backup_path..."
  gcloud compute ssh "$hostname" \
    --project "$project_id" --zone "$zone" --tunnel-through-iap \
    --command "sudo -u herm gsutil -m rsync -r -d '$backup_path' /home/herm"

  herm::log "restarting hermes-agent..."
  gcloud compute ssh "$hostname" \
    --project "$project_id" --zone "$zone" --tunnel-through-iap \
    --command "sudo systemctl start hermes-agent"

  herm::log "restore complete; verifying gateway..."
  sleep 5
  gcloud compute ssh "$hostname" \
    --project "$project_id" --zone "$zone" --tunnel-through-iap \
    --command "curl -fsS -H \"Authorization: Bearer \$(sudo cat /home/herm/.hermes/.api-token)\" http://localhost:8642/health"
}
