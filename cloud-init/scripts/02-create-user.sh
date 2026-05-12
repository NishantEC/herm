#!/usr/bin/env bash
# Create the unprivileged herm user. Idempotent.

set -euo pipefail

USER_NAME="herm"
HOME_DIR="/home/herm"

if ! id "$USER_NAME" >/dev/null 2>&1; then
  # Create with no login shell? No — we want to be able to `tailscale ssh` in.
  useradd --system --create-home --home-dir "$HOME_DIR" --shell /bin/bash "$USER_NAME"
fi

# Ensure /home/herm is owned by herm, mode 0700.
chown -R "$USER_NAME:$USER_NAME" "$HOME_DIR"
chmod 0700 "$HOME_DIR"

# Standard directories the agent will need.
sudo -u "$USER_NAME" mkdir -p "$HOME_DIR"/{.hermes,.config,workspaces}

echo "[02-create-user] user $USER_NAME ready at $HOME_DIR"
