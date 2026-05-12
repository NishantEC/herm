#!/usr/bin/env bash
# Apply the herm tool-allowlist policy from /opt/herm/config/hermes-tools.yaml
# to /home/herm/.hermes/config.yaml. Hermes' config is YAML; we merge in the
# allowed_tools / denied_tools lists under tools:.
#
# Uses Python (already on the VM via Hermes' installer) for YAML edit safety —
# bash sed would be fragile against multi-line list values.

set -euo pipefail

POLICY="/opt/herm/config/hermes-tools.yaml"
CONFIG="/home/herm/.hermes/config.yaml"

if [[ ! -f $POLICY ]]; then
  echo "[08-tool-allowlist] no policy file at $POLICY — skipping"
  exit 0
fi

if [[ ! -f $CONFIG ]]; then
  echo "[08-tool-allowlist] expected Hermes config at $CONFIG — skipping (Hermes may not have installed)"
  exit 0
fi

PY=/home/herm/.hermes/hermes-agent/venv/bin/python
if [[ ! -x $PY ]]; then
  echo "[08-tool-allowlist] no python at $PY — skipping"
  exit 0
fi

sudo -u herm "$PY" - "$POLICY" "$CONFIG" <<'PYEOF'
import sys, pathlib
try:
    import yaml
except ImportError:
    # PyYAML usually comes with Hermes' deps; install if not.
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pyyaml"])
    import yaml

policy_path, config_path = sys.argv[1], sys.argv[2]
policy = yaml.safe_load(pathlib.Path(policy_path).read_text()) or {}
config = yaml.safe_load(pathlib.Path(config_path).read_text()) or {}

tools = config.get("tools") or {}
allowed = policy.get("allowed_tools") or []
denied = policy.get("denied_tools") or []
tools["allowed"] = allowed
tools["denied"] = denied
config["tools"] = tools

pathlib.Path(config_path).write_text(yaml.safe_dump(config, sort_keys=False))
print(f"[08-tool-allowlist] applied: {len(allowed)} allowed, {len(denied)} denied tools")
PYEOF
