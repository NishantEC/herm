#!/usr/bin/env bash
# Reload systemd, enable hermes-agent + herm-backup.timer (+ herm-reaper.timer
# if 09-install-reaper.sh already enabled it).

set -euo pipefail

# Unit files were laid down earlier in the startup script. Reload + enable.
systemctl daemon-reload

systemctl enable --now hermes-agent.service
systemctl enable --now herm-backup.timer

# Lint check — verify units parse:
systemd-analyze verify /etc/systemd/system/hermes-agent.service
systemd-analyze verify /etc/systemd/system/herm-backup.service
systemd-analyze verify /etc/systemd/system/herm-backup.timer
systemd-analyze verify /etc/systemd/system/herm-reaper.service
systemd-analyze verify /etc/systemd/system/herm-reaper.timer

echo "[99-systemd-units] hermes-agent active; backup timer scheduled"
