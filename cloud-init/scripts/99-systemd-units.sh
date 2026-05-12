#!/usr/bin/env bash
# Reload systemd, enable hermes-agent + herm-backup.timer.

set -euo pipefail

# The unit files were laid down by cloud-init's write_files step. Just reload + enable.
systemctl daemon-reload

systemctl enable --now hermes-agent.service
systemctl enable --now herm-backup.timer

# Lint check — verify both units parse:
systemd-analyze verify /etc/systemd/system/hermes-agent.service
systemd-analyze verify /etc/systemd/system/herm-backup.service
systemd-analyze verify /etc/systemd/system/herm-backup.timer

echo "[99-systemd-units] hermes-agent active; backup timer scheduled"
