#!/usr/bin/env bash
# Install pinned base packages: node 24, tailscale, plus common dev tools.

set -euo pipefail

NODE_MAJOR=24
TAILSCALE_DEB_URL="https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg"
TAILSCALE_LIST_URL="https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list"

export DEBIAN_FRONTEND=noninteractive

# Force apt to use IPv4. The default GCE VPC has no IPv6 egress, but
# deb.debian.org resolves to AAAA records first — without this, package
# fetches hang on "Network is unreachable" before falling back. Killed
# the first v0.1 bootstrap; trivial to fix in a v0.4 paranoid-mode NAT
# allowlist by also pinning the resolver.
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99-herm-force-ipv4

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg lsb-release \
  git tmux ripgrep fzf jq rsync \
  uidmap

# Node 24 via NodeSource:
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
  > /etc/apt/sources.list.d/nodesource.list

# Tailscale:
curl -fsSL "$TAILSCALE_DEB_URL" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "$TAILSCALE_LIST_URL" -o /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y --no-install-recommends nodejs tailscale

# Verify versions are sane (pinning is enforced by NodeSource major + Tailscale stable channel;
# upgrade to pinned exact versions is a v0.2 refinement).
node --version
tailscale --version

echo "[03-install-base] base packages installed"
