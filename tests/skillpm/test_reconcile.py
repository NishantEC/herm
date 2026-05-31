from pathlib import Path
from skillpm import reconcile
from skillpm.lockfile import SkillEntry


def _mk_catalog_skill(root: Path, name: str):
    d = root / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\n---\n")


def test_installs_enabled_removes_extras(tmp_path: Path):
    catalog = tmp_path / "catalog"
    live = tmp_path / "live"
    for n in ("debug", "review-pr", "old"):
        _mk_catalog_skill(catalog, n)
    # 'old' is already live but not desired; 'debug' desired but absent.
    _mk_catalog_skill(live, "old")
    entries = {
        "debug": SkillEntry(name="debug", enabled=True),
        "review-pr": SkillEntry(name="review-pr", enabled=False),  # disabled -> not installed
    }
    summary = reconcile.reconcile(entries, catalog, live)
    assert (live / "debug" / "SKILL.md").is_file()
    assert not (live / "review-pr").exists()
    assert not (live / "old").exists()
    assert summary == {"installed": ["debug"], "removed": ["old"], "kept": []}


def test_only_touches_skill_dirs(tmp_path: Path):
    catalog = tmp_path / "catalog"
    live = tmp_path / "live"
    live.mkdir(parents=True)
    (live / "keepme.txt").write_text("not a skill")  # no SKILL.md -> untouched
    reconcile.reconcile({}, catalog, live)
    assert (live / "keepme.txt").is_file()
