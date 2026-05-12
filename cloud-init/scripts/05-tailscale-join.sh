#!/usr/bin/env bash
# Join the tailnet using the single-use auth key from Secret Manager.
# Then delete the Secret Manager secret so the key never sits around.

set -euo pipefail

PROJECT_ID=$(curl -fsSL -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/herm-project-id)
SECRET_ID=$(curl -fsSL -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/herm-ts-secret-id)
HOSTNAME=$(hostname)

# Pull the auth key:
ACCESS_TOKEN=$(curl -fsSL -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
  | jq -r .access_token)

AUTH_KEY=$(curl -fsSL -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${SECRET_ID}/versions/latest:access" \
  | jq -r .payload.data | base64 -d)

if [[ -z $AUTH_KEY ]]; then
  echo "[05-tailscale-join] empty auth key; aborting" >&2
  exit 1
fi

systemctl enable --now tailscaled

tailscale up \
  --authkey="$AUTH_KEY" \
  --hostname="$HOSTNAME" \
  --ssh \
  --accept-routes=false \
  --advertise-tags="tag:herm-vm"

# Verify join succeeded:
if ! tailscale status >/dev/null 2>&1; then
  echo "[05-tailscale-join] tailscale up reported success but status failed" >&2
  exit 1
fi

# Delete the Secret Manager secret entirely — the auth key is now useless to anyone
# who somehow gains read access later.
curl -fsSL -X DELETE \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${SECRET_ID}" \
  >/dev/null

echo "[05-tailscale-join] joined tailnet as $HOSTNAME; auth key secret deleted"
