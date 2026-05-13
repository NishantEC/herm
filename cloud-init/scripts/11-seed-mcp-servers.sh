#!/usr/bin/env bash
# Seed Hermes' config.yaml with MCP server registrations for the baseline
# productivity-tool integrations: Asana, Linear, Figma.
#
# All three use PAT-based community/upstream MCP servers (stdio transport via
# npx) because the official OAuth-based endpoints either don't support dynamic
# client registration (Asana, Linear) or return resource-indicator mismatches
# (the asana-mcp-server worker host). The PAT path is simpler, works without a
# headless OAuth dance, and is what survives across herm up --replace-vm.
#
# Each integration's token is left as PASTE_PAT_HERE; the owner edits
# ~/.hermes/config.yaml after first boot to fill them in. Tools that haven't
# had their token pasted yet fail-soft at startup (Hermes logs the connection
# attempt and continues without that toolset).
#
# Idempotent: only adds servers that aren't already in mcp_servers.

set -euo pipefail

HERMES_HOME="/home/herm/.hermes"
CONFIG="$HERMES_HOME/config.yaml"

if [[ ! -f $CONFIG ]]; then
  echo "[11-seed-mcp-servers] no Hermes config — skipping"
  exit 0
fi

PY=/home/herm/.hermes/hermes-agent/venv/bin/python
if [[ ! -x $PY ]]; then
  echo "[11-seed-mcp-servers] no python in Hermes venv — skipping"
  exit 0
fi

sudo -u herm "$PY" - "$CONFIG" <<'PYEOF'
import sys, pathlib, yaml

p = pathlib.Path(sys.argv[1])
c = yaml.safe_load(p.read_text())
mcps = c.get("mcp_servers") or {}

defaults = {
    "asana": {
        "command": "npx",
        "args": ["-y", "@roychri/mcp-server-asana"],
        "env": {"ASANA_ACCESS_TOKEN": "PASTE_PAT_HERE"},
    },
    "linear": {
        "command": "npx",
        "args": ["-y", "mcp-linear"],
        "env": {"LINEAR_API_KEY": "PASTE_PAT_HERE"},
    },
    "figma": {
        "command": "npx",
        "args": ["-y", "figma-developer-mcp", "--stdio"],
        "env": {"FIGMA_API_KEY": "PASTE_PAT_HERE"},
    },
}

added = []
for name, cfg in defaults.items():
    if name not in mcps:
        mcps[name] = cfg
        added.append(name)

c["mcp_servers"] = mcps
p.write_text(yaml.safe_dump(c, sort_keys=False))
print(f"[11-seed-mcp-servers] added MCP servers: {added or '(none — already present)'}")
print(f"[11-seed-mcp-servers] PATs to paste in {sys.argv[1]} after first boot:")
for name, cfg in defaults.items():
    for key, val in (cfg.get("env") or {}).items():
        if val == "PASTE_PAT_HERE":
            print(f"  {name}: {key}")
PYEOF
