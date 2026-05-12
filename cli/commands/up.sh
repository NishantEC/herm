# shellcheck shell=bash
# herm up — terraform apply.

herm::cmd::up() {
  herm::require_cmd terraform
  herm::require_cmd gcloud

  # --replace-vm forces terraform to destroy + recreate the VM, which is the
  # only way to re-trigger cloud-init after a metadata fix. The persistent disk
  # and Secret Manager secret are not affected.
  local replace_vm=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --replace-vm) replace_vm=1; shift ;;
      *)            herm::die "unknown flag: $1" ;;
    esac
  done

  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH — run 'herm init' first"
  fi

  # Terraform's google provider and gcs backend both need Application Default
  # Credentials, which are separate from 'gcloud auth login'. If missing, fail
  # fast with a clear instruction instead of letting terraform error opaquely.
  if [[ ! -f $HOME/.config/gcloud/application_default_credentials.json ]]; then
    herm::err "Application Default Credentials not configured."
    herm::err "Run this once, then re-run 'herm up':"
    herm::err "  gcloud auth application-default login"
    return 1
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

  # Render the GCE startup script by inlining the per-step scripts and systemd
  # units. Terraform consumes this via TF_VAR_startup_script (see vm.tf); the
  # script runs on first boot via google-startup-scripts.service.
  local rendered
  rendered="$(herm::__render_startup_script)"
  export TF_VAR_startup_script="$rendered"

  # Drop into terraform/. Use a per-project state bucket.
  local state_bucket="${project_id}-herm-tfstate"

  herm::tf init -reconfigure \
    -backend-config="bucket=${state_bucket}" \
    -input=false

  local -a apply_args=(
    apply
    -auto-approve
    -var "project_id=$project_id"
    -var "region=$region"
    -var "zone=$zone"
    -var "hostname=$hostname"
    -var "tailscale_auth_key=$auth_key"
  )
  if [[ $replace_vm -eq 1 ]]; then
    apply_args+=(-replace=google_compute_instance.herm)
    herm::log "--replace-vm: forcing VM replacement to re-trigger cloud-init"
  fi

  herm::tf "${apply_args[@]}"

  unset TF_VAR_startup_script

  herm::log "VM provisioned. Cloud-init takes ~6–10 min on cold boot."
  herm::log "Watch progress with: gcloud compute instances get-serial-port-output $hostname --zone $zone --project $project_id"
}

# Render a single bash startup script by inlining each step under
# cloud-init/scripts/ and each systemd unit under systemd/. GCE's
# google-startup-scripts.service runs this verbatim as root on first boot.
#
# Each inlined file is wrapped in a single-quoted heredoc (`<<'__HERM_FILE__'`)
# so the outer script does not expand `$VAR` references in the inlined content
# — the inner scripts run after they are on disk and expand their own vars then.
herm::__render_startup_script() {
  local script_dir="$HERM_REPO_ROOT/cloud-init/scripts"
  local unit_dir="$HERM_REPO_ROOT/systemd"
  local skills_dir="$HERM_REPO_ROOT/skills"
  local config_dir="$HERM_REPO_ROOT/config"

  # dest:src:mode triples for every fixed-path file the startup script writes.
  local files=(
    "/opt/herm/scripts/01-mount-disk.sh:$script_dir/01-mount-disk.sh:0755"
    "/opt/herm/scripts/02-create-user.sh:$script_dir/02-create-user.sh:0755"
    "/opt/herm/scripts/03-install-base.sh:$script_dir/03-install-base.sh:0755"
    "/opt/herm/scripts/04-install-hermes.sh:$script_dir/04-install-hermes.sh:0755"
    "/opt/herm/scripts/05-tailscale-join.sh:$script_dir/05-tailscale-join.sh:0755"
    "/opt/herm/scripts/07-seed-skills.sh:$script_dir/07-seed-skills.sh:0755"
    "/opt/herm/scripts/08-tool-allowlist.sh:$script_dir/08-tool-allowlist.sh:0755"
    "/opt/herm/scripts/09-install-reaper.sh:$script_dir/09-install-reaper.sh:0755"
    "/opt/herm/scripts/99-systemd-units.sh:$script_dir/99-systemd-units.sh:0755"
    "/etc/systemd/system/hermes-agent.service:$unit_dir/hermes-agent.service:0644"
    "/etc/systemd/system/herm-backup.service:$unit_dir/herm-backup.service:0644"
    "/etc/systemd/system/herm-backup.timer:$unit_dir/herm-backup.timer:0644"
    "/etc/systemd/system/herm-reaper.service:$unit_dir/herm-reaper.service:0644"
    "/etc/systemd/system/herm-reaper.timer:$unit_dir/herm-reaper.timer:0644"
    "/opt/herm/config/hermes-tools.yaml:$config_dir/hermes-tools.yaml:0644"
  )

  # Preamble: standard hardening, log file, dirs.
  cat <<'__HERM_PREAMBLE__'
#!/bin/bash
# herm — GCE startup script (rendered by cli/commands/up.sh).
# Runs once on first boot via google-startup-scripts.service.
set -euo pipefail
exec > >(tee -a /var/log/herm-startup.log) 2>&1
echo "[herm] startup begin at $(date -Iseconds)"
mkdir -p /opt/herm/scripts /opt/herm/skills /opt/herm/config /etc/systemd/system
__HERM_PREAMBLE__

  # Inline each fixed-path file.
  local entry dest src mode
  for entry in "${files[@]}"; do
    IFS=':' read -r dest src mode <<<"$entry"
    if [[ ! -f $src ]]; then
      herm::die "missing source file: $src"
    fi
    printf "\ncat > %s <<'__HERM_FILE__'\n" "$dest"
    cat "$src"
    printf "__HERM_FILE__\nchmod %s %s\n" "$mode" "$dest"
  done

  # Walk the skills/ tree and inline each SKILL.md (and any supporting files
  # next to it). Anthropic Agent-Skills spec: a skill is a directory containing
  # SKILL.md plus optional siblings. We replicate the directory layout under
  # /opt/herm/skills/, then 07-seed-skills.sh rsync's it into the herm user's
  # ~/.hermes/skills/herm/.
  if [[ -d $skills_dir ]]; then
    local skill_file rel skill_dest
    while IFS= read -r skill_file; do
      rel="${skill_file#"$skills_dir"/}"
      skill_dest="/opt/herm/skills/$rel"
      printf "\nmkdir -p %q\n" "$(dirname "$skill_dest")"
      printf "cat > %q <<'__HERM_SKILL_FILE__'\n" "$skill_dest"
      cat "$skill_file"
      printf "__HERM_SKILL_FILE__\nchmod 0644 %q\n" "$skill_dest"
    done < <(find "$skills_dir" -type f \( -name 'SKILL.md' -o -name '*.md' -o -name '*.txt' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \))
  fi

  # Read the reaper-enabled flag from config and export it so 09-install-reaper.sh
  # can act on it. Default: disabled.
  local reaper_enabled=0
  if reaper_enabled_val=$(herm::read_config "$HERM_CONFIG_PATH" reaper enabled 2>/dev/null); then
    if [[ "$reaper_enabled_val" == "true" ]]; then
      reaper_enabled=1
    fi
  fi
  printf "\nexport HERM_REAPER_ENABLED=%d\n" "$reaper_enabled"

  # Run the per-step scripts in order. 99-systemd-units.sh both writes the
  # unit-enable commands and finishes the bootstrap.
  cat <<'__HERM_RUN__'

/opt/herm/scripts/01-mount-disk.sh
/opt/herm/scripts/02-create-user.sh
/opt/herm/scripts/03-install-base.sh
/opt/herm/scripts/04-install-hermes.sh
/opt/herm/scripts/05-tailscale-join.sh
/opt/herm/scripts/07-seed-skills.sh
/opt/herm/scripts/08-tool-allowlist.sh
/opt/herm/scripts/09-install-reaper.sh
/opt/herm/scripts/99-systemd-units.sh

echo "[herm] startup complete at $(date -Iseconds)"
__HERM_RUN__
}
