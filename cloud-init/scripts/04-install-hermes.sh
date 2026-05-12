#!/usr/bin/env bash
# Install Hermes Agent as the herm user. Pinned version.
# Generates an API token on first boot and stashes it under /home/herm/.hermes/.

set -euo pipefail

HERMES_VERSION="1.4.0" # pinned; bumped via dependabot/manual review.
HERMES_HOME="/home/herm/.hermes"
HERMES_USER="herm"

sudo -u "$HERMES_USER" -H bash <<EOSU
set -euo pipefail
mkdir -p "$HERMES_HOME"

# Install Hermes Agent CLI globally for the herm user (uses npm --prefix to keep it user-scoped).
mkdir -p /home/herm/.npm-global
npm config set prefix /home/herm/.npm-global
export PATH="/home/herm/.npm-global/bin:\$PATH"
npm install -g "hermes-agent@$HERMES_VERSION"

# Generate API token if not already present:
if [[ ! -f "$HERMES_HOME/.api-token" ]]; then
  head -c 32 /dev/urandom | base64 | tr -d '\n' > "$HERMES_HOME/.api-token"
  chmod 0600 "$HERMES_HOME/.api-token"
fi

# Minimal .env so the API server binds to 0.0.0.0 inside the tailnet:
cat > "$HERMES_HOME/.env" <<EOENV
API_SERVER_HOST=0.0.0.0
API_SERVER_PORT=8642
HERMES_API_TOKEN_FILE=$HERMES_HOME/.api-token
EOENV
chmod 0600 "$HERMES_HOME/.env"
EOSU

echo "[04-install-hermes] hermes-agent@$HERMES_VERSION installed for $HERMES_USER"
