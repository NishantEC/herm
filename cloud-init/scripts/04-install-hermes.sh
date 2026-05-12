#!/usr/bin/env bash
# Install Hermes Agent as the herm user via the official one-line installer.
# Generates an API server bearer token on first boot and writes a non-interactive
# ~/.hermes/.env so the API server starts up without prompting.

set -euo pipefail

HERMES_USER="herm"
HERMES_INSTALLER_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"

# Run installer as the unprivileged herm user. < /dev/null guarantees any
# interactive prompts get EOF immediately (the installer is designed to be
# non-interactive but the safety belt is cheap).
sudo -u "$HERMES_USER" -H bash -c "curl -fsSL '$HERMES_INSTALLER_URL' | bash" < /dev/null

# Verify the installer landed the binary where the docs say it should.
if [[ ! -x /home/herm/.local/bin/hermes ]]; then
  echo "[04-install-hermes] expected /home/herm/.local/bin/hermes after install; aborting" >&2
  exit 1
fi

# Per-user .env that the API server reads.
sudo -u "$HERMES_USER" -H bash <<'EOSU'
set -euo pipefail
HERMES_HOME="/home/herm/.hermes"
mkdir -p "$HERMES_HOME"

# Generate API token if missing OR empty. (A bare `-f` check let stale
# zero-byte files from prior bootstrap attempts on the same persistent
# disk survive, leaving the gateway running with no usable bearer key.)
if [[ ! -s "$HERMES_HOME/.api-token" ]]; then
  head -c 32 /dev/urandom | base64 | tr -d '\n' > "$HERMES_HOME/.api-token"
  chmod 0600 "$HERMES_HOME/.api-token"
fi
API_TOKEN=$(cat "$HERMES_HOME/.api-token")

cat > "$HERMES_HOME/.env" <<EOENV
API_SERVER_ENABLED=true
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
API_SERVER_KEY=$API_TOKEN
EOENV
chmod 0600 "$HERMES_HOME/.env"
EOSU

HERMES_VERSION=$(/home/herm/.local/bin/hermes --version 2>&1 | head -1 || echo "unknown")
echo "[04-install-hermes] hermes installed: $HERMES_VERSION"
