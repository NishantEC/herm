"""Restart the Hermes gateway so reconciled skills take effect.

Skills are discovered at gateway startup, so a mutation only takes effect after a
restart. We prefer the per-user systemd unit -- a clean, graceful restart the
`herm` user can issue without root. If that unit isn't present we fall back to a
graceful SIGTERM on the gateway process, which a system-level unit with
`Restart=always` respawns. We never SIGKILL (`pkill -9`) -- that loses in-flight
state ungracefully.
"""
from __future__ import annotations

import os
import subprocess


def _user_env() -> dict[str, str]:
    env = dict(os.environ)
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return env


def reload(unit: str = "hermes-gateway") -> str:
    """Restart the gateway. Returns a short description of what was done."""
    env = _user_env()
    probe = subprocess.run(
        ["systemctl", "--user", "is-active", unit],
        capture_output=True, text=True, env=env,
    )
    if probe.returncode == 0:
        subprocess.run(["systemctl", "--user", "restart", unit], env=env, check=False)
        return f"systemctl --user restart {unit}"
    # No user unit: graceful signal; a Restart=always system unit respawns it.
    subprocess.run(["pkill", "-TERM", "-f", "hermes gateway"], check=False)
    return "pkill -TERM 'hermes gateway' (systemd respawn)"
