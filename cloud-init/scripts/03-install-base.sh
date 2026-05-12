#!/usr/bin/env bash
# Install base packages: tailscale (needed by step 05) and a minimal toolchain.
# The Hermes Agent installer (step 04) handles Python / Node / uv / ripgrep /
# ffmpeg itself — only Git is a required prereq for it.

set -euo pipefail

TAILSCALE_DEB_URL="https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg"
TAILSCALE_LIST_URL="https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list"

export DEBIAN_FRONTEND=noninteractive

# Force apt to IPv4. The default GCE VPC has no IPv6 egress, but
# deb.debian.org resolves to AAAA records first — without this, package
# fetches hang on "Network is unreachable" before falling back.
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99-herm-force-ipv4

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release \
  git tmux jq rsync \
  uidmap

# Tailscale:
curl -fsSL "$TAILSCALE_DEB_URL" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "$TAILSCALE_LIST_URL" -o /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y --no-install-recommends tailscale

tailscale --version

echo "[03-install-base] base packages installed"
