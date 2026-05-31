#!/usr/bin/env bash
# Boot-time skill seeding via the skillpm engine.
#
# Installs the engine + catalog into HERM-OWNED paths under ~/.hermes (so the
# herm user can later update them over SSH without root — `herm skills deploy`),
# then reconciles the live skill set from the lockfile. Back-compat: with no
# lockfile, skillpm seeds the catalog AND preserves any skills already on the
# persistent disk, so nothing the owner added gets dropped.
#
# Runs as root (cloud-init). No gateway reload here — systemd starts the gateway
# after this step, so it picks up the reconciled skills on its first start.

set -euo pipefail

HERMES=/home/herm/.hermes
PY="$HERMES/hermes-agent/venv/bin/python"

if [[ ! -x $PY ]]; then
  echo "[07-seed-skills] no Hermes venv python — skipping"
  exit 0
fi
if [[ ! -d /opt/herm/skillpm ]]; then
  echo "[07-seed-skills] no skillpm shipped — skipping"
  exit 0
fi

# Install engine + catalog into herm-owned locations (clean replace).
rm -rf "$HERMES/skillpm" "$HERMES/skill-catalog"
cp -a /opt/herm/skillpm "$HERMES/skillpm"
cp -a /opt/herm/skills "$HERMES/skill-catalog"
chown -R herm:herm "$HERMES/skillpm" "$HERMES/skill-catalog"

# Reconcile as the herm user against the herm-owned engine/catalog/lockfile.
sudo -u herm env PYTHONPATH="$HERMES" "$PY" -m skillpm sync

echo "[07-seed-skills] reconciled skills via skillpm"
