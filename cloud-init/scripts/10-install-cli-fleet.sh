#!/usr/bin/env bash
# Install the CLI fleet that Hermes' skills + the human owner use:
# claude (Anthropic), gh (GitHub), gemini (Google), codex (OpenAI), opencode.
#
# All install per-user into /home/herm/.local/bin or /home/herm/.npm-global/bin.
# Each tool's auth/login flow is a separate manual step the owner runs via
# `herm login <provider>` (or directly via `tailscale ssh herm@herm-vm`).
#
# Idempotent: re-runs are safe.

set -euo pipefail

HERMES_USER="herm"

sudo -u "$HERMES_USER" -H bash <<'EOSU'
set -euo pipefail
mkdir -p ~/.local/bin

# ---- gh (GitHub CLI) — official tarball, no apt needed ---------------------
if ! command -v gh >/dev/null 2>&1; then
  GH_VERSION=2.59.0
  ARCH=$(uname -m); [[ "$ARCH" == "x86_64" ]] && ARCH=amd64
  curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" -o /tmp/gh.tar.gz
  tar xzf /tmp/gh.tar.gz -C /tmp/
  cp /tmp/gh_${GH_VERSION}_linux_${ARCH}/bin/gh ~/.local/bin/gh
  chmod +x ~/.local/bin/gh
  rm -rf /tmp/gh.tar.gz /tmp/gh_${GH_VERSION}_linux_${ARCH}
  echo "[10-install-cli-fleet] gh $(gh --version | head -1)"
fi

# ---- claude (Anthropic), gemini (Google), codex (OpenAI), opencode ---------
# All ship as npm globals. Hermes' bundled npm prefix is /home/herm/.npm-global;
# we symlink the resulting binaries into ~/.local/bin for a consistent PATH.
NPM=/home/herm/.hermes/node/bin/npm
for pkg in \
  "@anthropic-ai/claude-code:claude" \
  "@google/gemini-cli:gemini" \
  "@openai/codex:codex" \
  "opencode-ai:opencode"
do
  PKG_NAME="${pkg%%:*}"
  BIN_NAME="${pkg##*:}"
  if ! command -v "$BIN_NAME" >/dev/null 2>&1; then
    "$NPM" install -g "$PKG_NAME" >/dev/null
    if [[ -x /home/herm/.npm-global/bin/$BIN_NAME ]]; then
      ln -sf "/home/herm/.npm-global/bin/$BIN_NAME" "$HOME/.local/bin/$BIN_NAME"
    fi
    echo "[10-install-cli-fleet] $BIN_NAME installed"
  fi
done

# ---- goose: handled separately (its installer has a tarball quirk on Debian) -
# Skip for now; user can run `herm login goose` later which retries with the
# right flags. Not auto-installing avoids a hard failure during cloud-init.

echo "[10-install-cli-fleet] CLI fleet ready:"
for c in claude gh gemini codex opencode; do
  if command -v "$c" >/dev/null 2>&1; then
    echo "  ✓ $c"
  else
    echo "  ✗ $c (install failed; rerun manually)"
  fi
done
EOSU
