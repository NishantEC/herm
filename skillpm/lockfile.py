"""Read/write the herm skills lockfile (skills.toml).

The lockfile is the declarative desired-state for installed skills. We read it
with tomllib (3.11+) / tomli, and EMIT it by rendering the flat schema directly,
because the stdlib ships no TOML writer (and this repo avoids extra deps).
"""
from __future__ import annotations

import dataclasses
from pathlib import Path

try:  # Python 3.11+
    import tomllib
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore


@dataclasses.dataclass
class SkillEntry:
    name: str
    source: str = "catalog"          # catalog | git | local
    enabled: bool = True
    url: str | None = None
    ref: str | None = None
    subdir: str | None = None
    path: str | None = None


def load(path: Path) -> dict[str, SkillEntry]:
    if not path.exists():
        return {}
    data = tomllib.loads(path.read_text())
    out: dict[str, SkillEntry] = {}
    for name, body in (data.get("skills") or {}).items():
        out[name] = SkillEntry(
            name=name,
            source=body.get("source", "catalog"),
            enabled=bool(body.get("enabled", True)),
            url=body.get("url"),
            ref=body.get("ref"),
            subdir=body.get("subdir"),
            path=body.get("path"),
        )
    return out


def _q(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def dumps(entries: dict[str, SkillEntry]) -> str:
    lines: list[str] = []
    for name in sorted(entries):
        e = entries[name]
        lines.append(f"[skills.{name}]")
        lines.append(f"source  = {_q(e.source)}")
        for key, val in (("url", e.url), ("ref", e.ref), ("subdir", e.subdir), ("path", e.path)):
            if val is not None:
                lines.append(f"{key:<7} = {_q(val)}")
        lines.append(f"enabled = {'true' if e.enabled else 'false'}")
        lines.append("")
    return ("\n".join(lines).rstrip() + "\n") if lines else ""


def save(path: Path, entries: dict[str, SkillEntry]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dumps(entries))
