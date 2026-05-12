# shellcheck shell=bash
# herm upgrade — snapshot the PD-SSD, run the latest cloud-init scripts on
# the existing VM, restart units, verify, auto-rollback on failure.

herm::cmd::upgrade() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  herm::require_cmd gcloud
  herm::require_cmd terraform

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  local snapshot_name
  snapshot_name="herm-pre-upgrade-$(date -u +%Y%m%dT%H%M%SZ)"

  herm::log "snapshotting persistent disk as $snapshot_name..."
  gcloud compute snapshots create "$snapshot_name" \
    --source-disk=herm-data \
    --source-disk-zone="$zone" \
    --project="$project_id" \
    --storage-location="${zone%-*}" \
    --quiet

  herm::log "running upgrade scripts on $hostname..."
  local upgrade_log
  upgrade_log=$(mktemp)
  trap 'rm -f "$upgrade_log"' EXIT

  if ! gcloud compute ssh "$hostname" \
    --project "$project_id" \
    --zone "$zone" \
    --tunnel-through-iap \
    --command "sudo bash -lc '
      set -euo pipefail
      /opt/herm/scripts/03-install-base.sh
      /opt/herm/scripts/04-install-hermes.sh
      systemctl daemon-reload
      systemctl restart hermes-agent
      sleep 5
      curl -fsS -H \"Authorization: Bearer \$(cat /home/herm/.hermes/.api-token)\" http://localhost:8642/health
    '" 2>&1 | tee "$upgrade_log"; then
    herm::err "upgrade failed; rolling back to snapshot $snapshot_name..."
    herm::__upgrade_rollback "$snapshot_name" "$project_id" "$zone" "$hostname"
    return 1
  fi

  herm::log "upgrade complete and verified"
  herm::log "snapshot kept as $snapshot_name (auto-prune of snapshots >7 days happens on next upgrade)"

  # Prune old snapshots
  local cutoff
  cutoff=$(date -u -v-7d +%Y%m%d 2>/dev/null || date -u -d '-7 days' +%Y%m%d)
  for s in $(gcloud compute snapshots list \
    --project "$project_id" \
    --filter="name~^herm-pre-upgrade-" \
    --format='value(name)'); do
    local s_date="${s#herm-pre-upgrade-}"
    s_date="${s_date%%T*}"
    if [[ "$s_date" < "$cutoff" ]]; then
      herm::log "pruning old snapshot: $s"
      gcloud compute snapshots delete "$s" --project "$project_id" --quiet || true
    fi
  done
}

herm::__upgrade_rollback() {
  local snapshot="$1" project_id="$2" zone="$3" hostname="$4"
  herm::warn "rollback: detaching disk, restoring from snapshot, reattaching"
  gcloud compute instances stop "$hostname" --project "$project_id" --zone "$zone" --quiet
  gcloud compute instances detach-disk "$hostname" --disk=herm-data --project "$project_id" --zone "$zone" --quiet
  gcloud compute disks delete herm-data --project "$project_id" --zone "$zone" --quiet
  gcloud compute disks create herm-data --source-snapshot="$snapshot" --project "$project_id" --zone "$zone" --type=pd-ssd --quiet
  gcloud compute instances attach-disk "$hostname" --disk=herm-data --device-name=herm-data --project "$project_id" --zone "$zone" --quiet
  gcloud compute instances start "$hostname" --project "$project_id" --zone "$zone" --quiet
  herm::log "rollback complete; pre-upgrade state restored"
}
