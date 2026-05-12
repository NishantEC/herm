# shellcheck shell=bash
# herm nuke — destroy EVERYTHING, including the persistent disk and the backup bucket.

herm::cmd::nuke() {
  herm::require_cmd terraform
  herm::require_cmd gcloud
  herm::require_cmd gsutil

  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local project_id region zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  region="$(herm::read_config "$HERM_CONFIG_PATH" gcp region)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  herm::warn "This will DELETE the VM, the persistent disk, the backup bucket and its versions."
  if ! herm::confirm "Are you absolutely sure?"; then
    herm::log "aborted"
    return 0
  fi
  local typed
  read -r -p "Type the project ID '$project_id' to confirm: " typed
  if [[ $typed != "$project_id" ]]; then
    herm::die "confirmation mismatch; aborted"
  fi

  # Empty the backup bucket first (force_destroy=false on the resource).
  local bucket="${project_id}-herm-backups"
  if gsutil ls "gs://$bucket" >/dev/null 2>&1; then
    herm::log "emptying gs://$bucket..."
    gsutil -m rm -ra "gs://$bucket/**" || true
  fi

  herm::tf destroy \
    -auto-approve \
    -var "project_id=$project_id" \
    -var "region=$region" \
    -var "zone=$zone" \
    -var "hostname=$hostname" \
    -var "tailscale_auth_key=unused-during-destroy"

  # Disk has prevent_destroy=true; remove the lifecycle and re-destroy.
  herm::warn "Persistent disk has prevent_destroy=true. To remove it:"
  herm::warn "  1. Comment out the lifecycle block in terraform/disk.tf"
  herm::warn "  2. Rerun 'herm nuke'"
  herm::warn "(This is a v0.1 friction point; v0.2 adds a --force flag that toggles the lifecycle automatically.)"
}
