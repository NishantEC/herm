#!/usr/bin/env bash
# Install the herm-reaper script + (optionally) enable the timer.
#
# Reaper logic: every 30 min, check 'tailscale status --json' for peers
# that have been online in the last IDLE_HOURS hours. If none, halt the VM.
# The VM remains in GCE as a stopped instance; 'herm up' (no replace) or
# 'gcloud compute instances start herm-vm' brings it back online.

set -euo pipefail

IDLE_HOURS=${HERM_REAPER_IDLE_HOURS:-168}   # default 7 days

cat > /usr/local/bin/herm-reaper.sh <<EOSCRIPT
#!/usr/bin/env bash
# herm-reaper — halt the VM if no tailnet peer has been seen for >\$IDLE_HOURS.
# Driven by herm-reaper.timer.

set -euo pipefail

IDLE_HOURS=$IDLE_HOURS
LOG_TAG="herm-reaper"

# Require an active tailnet session; if tailscaled isn't reachable, do nothing
# (don't accidentally halt a healthy VM because of a Tailscale outage).
if ! tailscale status --json >/tmp/ts-status.json 2>/dev/null; then
  logger -t \$LOG_TAG "tailscaled unreachable; skipping reaper this run"
  exit 0
fi

# Find the latest LastSeen across all peers. Anything more recent than now -
# IDLE_HOURS hours counts as "owner is around."
now_epoch=\$(date +%s)
cutoff=\$((now_epoch - IDLE_HOURS * 3600))

most_recent=\$(jq -r '
  [.Peer[]? | select(.UserID != 0) | .LastSeen | sub("\\\\.[0-9]+Z\$"; "Z") | fromdate]
  | max // 0
' /tmp/ts-status.json 2>/dev/null || echo 0)

if [[ \$most_recent -gt \$cutoff ]]; then
  logger -t \$LOG_TAG "owner active (last seen \$((now_epoch - most_recent))s ago); not halting"
  exit 0
fi

logger -t \$LOG_TAG "no owner peer in \$IDLE_HOURS hours; halting VM"
systemctl poweroff
EOSCRIPT
chmod 0755 /usr/local/bin/herm-reaper.sh

# Reaper is OPT-IN. Only enable the timer if the owner explicitly turned it
# on via ~/.config/herm/config.toml [reaper] enabled = true (this is checked
# at apply time and surfaced via cloud-init env var HERM_REAPER_ENABLED=1).
if [[ "${HERM_REAPER_ENABLED:-0}" == "1" ]]; then
  systemctl enable --now herm-reaper.timer
  echo "[09-install-reaper] reaper enabled — VM halts after \$IDLE_HOURS hours idle"
else
  echo "[09-install-reaper] reaper installed but disabled (set [reaper] enabled=true in config.toml + herm upgrade to enable)"
fi
