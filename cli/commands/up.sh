# shellcheck shell=bash
# herm up — terraform apply.

herm::cmd::up() {
  herm::require_cmd terraform
  herm::require_cmd gcloud

  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH — run 'herm init' first"
  fi

  local project_id region zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  region="$(herm::read_config "$HERM_CONFIG_PATH" gcp region)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  # Tailscale auth key: ask the owner each time (cheaper than caching).
  local auth_key
  read -r -s -p "Paste a single-use Tailscale auth key (https://login.tailscale.com/admin/settings/keys): " auth_key
  echo
  if [[ -z $auth_key ]]; then
    herm::die "no auth key provided"
  fi

  # Render cloud-init.yaml by inlining base64-encoded scripts and units.
  local rendered
  rendered="$(herm::__render_cloud_init)"
  local tmp
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  printf '%s' "$rendered" > "$tmp"

  # Drop into terraform/. Use a per-project state bucket.
  local state_bucket="${project_id}-herm-tfstate"

  herm::tf init -reconfigure \
    -backend-config="bucket=${state_bucket}" \
    -input=false

  herm::tf apply \
    -auto-approve \
    -var "project_id=$project_id" \
    -var "region=$region" \
    -var "zone=$zone" \
    -var "hostname=$hostname" \
    -var "tailscale_auth_key=$auth_key"

  herm::log "VM provisioned. Cloud-init takes ~6–10 min on cold boot."
  herm::log "Watch progress with: gcloud compute instances get-serial-port-output $hostname --zone $zone --project $project_id"
}

# Render cloud-init.yaml by base64-encoding each script and unit, replacing the BASE64_* placeholders.
herm::__render_cloud_init() {
  local template="$HERM_REPO_ROOT/cloud-init/cloud-init.yaml"
  local script_dir="$HERM_REPO_ROOT/cloud-init/scripts"
  local unit_dir="$HERM_REPO_ROOT/systemd"

  local content
  content="$(<"$template")"

  local mappings=(
    "BASE64_01:$script_dir/01-mount-disk.sh"
    "BASE64_02:$script_dir/02-create-user.sh"
    "BASE64_03:$script_dir/03-install-base.sh"
    "BASE64_04:$script_dir/04-install-hermes.sh"
    "BASE64_05:$script_dir/05-tailscale-join.sh"
    "BASE64_99:$script_dir/99-systemd-units.sh"
    "BASE64_UNIT_HERMES:$unit_dir/hermes-agent.service"
    "BASE64_UNIT_BACKUP_SVC:$unit_dir/herm-backup.service"
    "BASE64_UNIT_BACKUP_TIMER:$unit_dir/herm-backup.timer"
  )

  local m placeholder path encoded
  for m in "${mappings[@]}"; do
    placeholder="${m%%:*}"
    path="${m#*:}"
    if [[ ! -f $path ]]; then
      herm::die "missing source file for $placeholder: $path"
    fi
    encoded="$(base64 -w 0 "$path" 2>/dev/null || base64 < "$path" | tr -d '\n')"
    content="${content//$placeholder/$encoded}"
  done

  printf '%s' "$content"
}
