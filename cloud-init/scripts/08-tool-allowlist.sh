#!/usr/bin/env bash
# Apply the herm toolset-disable policy from /opt/herm/config/hermes-tools.yaml
# to /home/herm/.hermes/config.yaml by merging into agent.disabled_toolsets.
#
# Uses Hermes' own venv Python so PyYAML is guaranteed present.

set -euo pipefail

POLICY="/opt/herm/config/hermes-tools.yaml"
CONFIG="/home/herm/.hermes/config.yaml"
PY=/home/herm/.hermes/hermes-agent/venv/bin/python

if [[ ! -f $POLICY ]]; then
  echo "[08-tool-allowlist] no policy at $POLICY — skipping"
  exit 0
fi
if [[ ! -f $CONFIG ]]; then
  echo "[08-tool-allowlist] expected Hermes config at $CONFIG — skipping (Hermes may not have installed)"
  exit 0
fi
if [[ ! -x $PY ]]; then
  echo "[08-tool-allowlist] no python at $PY — skipping"
  exit 0
fi

sudo -u herm "$PY" - "$POLICY" "$CONFIG" <<'PYEOF'
import sys, pathlib, yaml

policy_path, config_path = sys.argv[1], sys.argv[2]
policy = yaml.safe_load(pathlib.Path(policy_path).read_text()) or {}
config = yaml.safe_load(pathlib.Path(config_path).read_text()) or {}

policy_disabled = list(policy.get("disabled_toolsets") or [])
agent = config.get("agent") or {}
current = list(agent.get("disabled_toolsets") or [])

# Union — preserve any user-added entries, add ours, dedupe stable-order.
merged = []
for t in current + policy_disabled:
    if t not in merged:
        merged.append(t)
agent["disabled_toolsets"] = merged
config["agent"] = agent

# Strip the no-op stub key from an earlier version of this script.
config.pop("tools", None)

pathlib.Path(config_path).write_text(yaml.safe_dump(config, sort_keys=False))
print(f"[08-tool-allowlist] agent.disabled_toolsets now: {merged}")
PYEOF
