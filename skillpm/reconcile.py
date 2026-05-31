"""Reconcile the live skills dir to the lockfile's enabled set.

Operates ONLY within `skills_dir` (the herm/ namespace). User-authored skills
in sibling namespaces (~/.hermes/skills/<other>/) live outside skills_dir and
are never touched. Phase 1 materialises catalog-source skills only; git/local
sources are handled in later phases.
"""
from __future__ import annotations

import shutil
from pathlib import Path

from .lockfile import SkillEntry


def desired(entries: dict[str, SkillEntry]) -> set[str]:
    return {n for n, e in entries.items() if e.enabled}


def actual(skills_dir: Path) -> set[str]:
    if not skills_dir.is_dir():
        return set()
    return {p.parent.name for p in skills_dir.glob("*/SKILL.md")}


def reconcile(entries: dict[str, SkillEntry], catalog_dir: Path, skills_dir: Path) -> dict:
    skills_dir.mkdir(parents=True, exist_ok=True)
    want = desired(entries)
    have = actual(skills_dir)
    installed: list[str] = []
    removed: list[str] = []
    for name in sorted(want - have):
        src = catalog_dir / name
        if not (src / "SKILL.md").is_file():
            continue  # non-catalog source -- later phases
        shutil.copytree(src, skills_dir / name, dirs_exist_ok=True)
        installed.append(name)
    for name in sorted(have - want):
        shutil.rmtree(skills_dir / name)
        removed.append(name)
    return {"installed": installed, "removed": removed, "kept": sorted(want & have)}
