# shellcheck shell=bash
# herm init — one-time: configure ~/.config/herm/config.toml, enable APIs, create state bucket.

herm::cmd::init() {
  herm::require_cmd gcloud
  herm::require_cmd gsutil

  local config_dir
  config_dir="$(dirname "$HERM_CONFIG_PATH")"
  mkdir -p "$config_dir"
  chmod 0700 "$config_dir"

  if [[ -f $HERM_CONFIG_PATH ]]; then
    herm::warn "config already exists at $HERM_CONFIG_PATH"
    if ! herm::confirm "Overwrite?"; then
      return 0
    fi
  fi

  local project_id billing_account region zone owner_tag hostname budget
  read -r -p "GCP project ID: " project_id
  read -r -p "GCP billing account ID (optional): " billing_account
  read -r -p "Region [us-central1]: " region; region="${region:-us-central1}"
  read -r -p "Zone [us-central1-a]: " zone; zone="${zone:-us-central1-a}"
  read -r -p "Tailscale owner tag (e.g. tag:nishant): " owner_tag
  read -r -p "VM hostname [herm-vm]: " hostname; hostname="${hostname:-herm-vm}"
  read -r -p "Monthly budget USD [25]: " budget; budget="${budget:-25}"

  cat > "$HERM_CONFIG_PATH" <<EOF
[gcp]
project_id     = "$project_id"
billing_account = "$billing_account"
region         = "$region"
zone           = "$zone"

[vm]
machine_type = "e2-small"
disk_size_gb = 10

[tailscale]
owner_tag = "$owner_tag"
hostname  = "$hostname"

[budget]
monthly_usd = $budget
EOF
  chmod 0600 "$HERM_CONFIG_PATH"
  herm::log "config written to $HERM_CONFIG_PATH"

  # Enable required APIs.
  herm::log "enabling required GCP APIs..."
  gcloud --project "$project_id" services enable \
    compute.googleapis.com \
    secretmanager.googleapis.com \
    storage.googleapis.com \
    iap.googleapis.com \
    logging.googleapis.com

  # Create the Terraform state bucket if missing.
  local state_bucket="${project_id}-herm-tfstate"
  if ! gsutil ls "gs://$state_bucket" >/dev/null 2>&1; then
    herm::log "creating terraform state bucket gs://$state_bucket"
    gsutil mb -p "$project_id" -l "$region" -b on "gs://$state_bucket"
    gsutil versioning set on "gs://$state_bucket"
  else
    herm::log "terraform state bucket already exists: gs://$state_bucket"
  fi

  # Budget alert.
  if [[ -n $billing_account ]]; then
    herm::log "creating GCP budget alert at \$${budget}/mo"
    gcloud billing budgets create \
      --billing-account="$billing_account" \
      --display-name="herm-budget" \
      --budget-amount="${budget}USD" \
      --threshold-rule=percent=0.5 \
      --threshold-rule=percent=0.8 \
      --threshold-rule=percent=1.0 \
      --filter-projects="projects/$project_id" \
      2>/dev/null || herm::warn "budget create failed (already exists?) — set one manually in console"
  else
    herm::warn "no billing account provided — skipping budget alert. Set one in console!"
  fi

  herm::log "init complete. Next: 'herm up'"
}
