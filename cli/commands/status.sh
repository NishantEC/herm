# shellcheck shell=bash
# herm status — summarize the current deployment.

herm::cmd::status() {
  herm::require_cmd terraform
  herm::require_cmd gcloud
  herm::require_cmd tailscale

  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::warn "no config at $HERM_CONFIG_PATH — run 'herm init' first"
    return 1
  fi

  local project_id hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  herm::log "project:   $project_id"
  herm::log "hostname:  $hostname"

  # Terraform state inspection — silent if no state yet.
  if herm::tf state list >/dev/null 2>&1; then
    local vm_status
    vm_status="$(gcloud compute instances describe "$hostname" \
      --project "$project_id" \
      --zone "$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)" \
      --format='value(status)' 2>/dev/null || echo 'NOT_FOUND')"
    herm::log "vm status: $vm_status"
  else
    herm::log "vm status: (no terraform state — run 'herm up')"
  fi

  # Tailnet reachability:
  if tailscale status --json 2>/dev/null | grep -q "\"$hostname\""; then
    herm::log "tailnet:   reachable"
  else
    herm::log "tailnet:   not in current tailnet status output"
  fi
}
