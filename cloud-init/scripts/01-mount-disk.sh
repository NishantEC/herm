#!/usr/bin/env bash
# Mount the herm-data persistent disk at /home/herm.
# Idempotent: first boot formats; later boots just mount.

set -euo pipefail

DEVICE="/dev/disk/by-id/google-herm-data"
MOUNT="/home/herm"

if [[ ! -e $DEVICE ]]; then
  echo "[01-mount-disk] expected device $DEVICE not present; aborting" >&2
  exit 1
fi

if ! blkid "$DEVICE" >/dev/null 2>&1; then
  echo "[01-mount-disk] formatting $DEVICE as ext4"
  mkfs.ext4 -L herm-data -m 1 "$DEVICE"
fi

mkdir -p "$MOUNT"

if ! mountpoint -q "$MOUNT"; then
  UUID=$(blkid -s UUID -o value "$DEVICE")
  # Idempotent fstab edit:
  if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID $MOUNT ext4 defaults,nofail,discard 0 2" >> /etc/fstab
  fi
  mount "$MOUNT"
fi

echo "[01-mount-disk] $MOUNT is mounted: $(df -h "$MOUNT" | tail -1)"
