# shellcheck shell=bash
# herm down — terraform destroy of VM + ephemeral resources.
# Persistent disk and backup bucket survive (their TF resources have prevent_destroy / force_destroy=false).

herm::cmd::down() {
  herm::require_cmd terraform

  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  local project_id region zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  region="$(herm::read_config "$HERM_CONFIG_PATH" gcp region)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  if ! herm::confirm "Destroy the herm VM in $project_id? (disk and backup will be kept)"; then
    herm::log "aborted"
    return 0
  fi

  # Selectively destroy: explicitly NOT the persistent disk or the backup bucket.
  herm::tf destroy \
    -auto-approve \
    -target=google_compute_instance.herm \
    -target=google_secret_manager_secret_version.tailscale_auth_key \
    -target=google_secret_manager_secret.tailscale_auth_key \
    -target=google_compute_firewall.deny_all_ingress \
    -target=google_compute_firewall.iap_ssh \
    -target=google_compute_subnetwork.herm \
    -target=google_compute_network.herm \
    -var "project_id=$project_id" \
    -var "region=$region" \
    -var "zone=$zone" \
    -var "hostname=$hostname" \
    -var "tailscale_auth_key=unused-during-destroy"

  herm::log "VM destroyed. Persistent disk and backup bucket remain. Run 'herm nuke' to remove them too."
}
