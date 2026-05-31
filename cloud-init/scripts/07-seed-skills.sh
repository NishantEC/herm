#!/usr/bin/env bash
# Reconcile the herm skill set to the declarative lockfile via the skillpm engine.
# Replaces the old blind rsync of /opt/herm/skills. Back-compat: on first boot
# (no lockfile) skillpm seeds every catalog skill enabled — matching prior behavior.
#
# Idempotent. Operates only within ~/.hermes/skills/herm/; user-authored skills
# in sibling namespaces are untouched.

set -euo pipefail

PY=/home/herm/.hermes/hermes-agent/venv/bin/python
SKILLPM=/opt/herm/skillpm

if [[ ! -x $PY ]]; then
  echo "[07-seed-skills] no Hermes venv python — skipping"
  exit 0
fi
if [[ ! -d $SKILLPM ]]; then
  echo "[07-seed-skills] no skillpm shipped — skipping"
  exit 0
fi

sudo -u herm \
  PYTHONPATH=/opt/herm \
  SKILLPM_CATALOG=/opt/herm/skills \
  "$PY" -m skillpm sync
