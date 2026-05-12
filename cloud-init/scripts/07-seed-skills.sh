#!/usr/bin/env bash
# Copy the repo's skills/ into /home/herm/.hermes/skills/herm/ so Hermes
# auto-discovers them on next start. The herm/ subdirectory namespace
# keeps our skills separate from upstream-bundled and user-authored ones.
#
# Idempotent. Doesn't overwrite user-authored skills outside herm/.

set -euo pipefail

SRC="/opt/herm/skills"
DEST="/home/herm/.hermes/skills/herm"

if [[ ! -d $SRC ]]; then
  echo "[07-seed-skills] no skills/ shipped — skipping"
  exit 0
fi

mkdir -p "$DEST"
chown -R herm:herm /home/herm/.hermes/skills

# rsync with --delete only inside herm/, so user-authored skills under
# /home/herm/.hermes/skills/<other-name>/ are preserved.
sudo -u herm rsync -a --delete "$SRC/" "$DEST/"

echo "[07-seed-skills] seeded $(find "$DEST" -name SKILL.md | wc -l | tr -d ' ') skills into $DEST"
