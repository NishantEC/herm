# shellcheck shell=bash
# herm rotate — regenerate the Hermes API server bearer token, update the
# VM's .env, restart hermes-agent, and print the new value once.

herm::cmd::rotate() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH"
  fi

  herm::require_cmd gcloud

  local target="${1:-hermes}"
  case "$target" in
    hermes)
      ;;
    *)
      herm::die "rotation for '$target' not implemented in v0.2 (only 'hermes')"
      ;;
  esac

  local project_id zone hostname
  project_id="$(herm::read_config "$HERM_CONFIG_PATH" gcp project_id)"
  zone="$(herm::read_config "$HERM_CONFIG_PATH" gcp zone)"
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"

  herm::log "rotating Hermes API token on $hostname..."
  local remote
  remote=$(gcloud compute ssh "$hostname" \
    --project "$project_id" \
    --zone "$zone" \
    --tunnel-through-iap \
    --command "sudo bash -c '
      set -euo pipefail
      NEW=\$(head -c 32 /dev/urandom | base64 | tr -d \"\\n\")
      echo \"\$NEW\" > /home/herm/.hermes/.api-token
      chown herm:herm /home/herm/.hermes/.api-token
      chmod 0600 /home/herm/.hermes/.api-token
      sed -i \"s|^API_SERVER_KEY=.*|API_SERVER_KEY=\$NEW|\" /home/herm/.hermes/.env
      systemctl restart hermes-agent
      sleep 3
      curl -fsS -H \"Authorization: Bearer \$NEW\" http://localhost:8642/health >/dev/null
      echo \"\$NEW\"
    '" 2>&1) || {
      herm::err "rotation failed"
      echo "$remote" >&2
      return 1
    }

  local new_token
  new_token=$(printf '%s\n' "$remote" | tail -1 | tr -d '\r')
  echo
  herm::log "rotation complete"
  echo "  New token: $new_token"
  echo
  herm::warn "copy this value into Hermes Desktop / any client right now — it will not be re-displayable."
}
