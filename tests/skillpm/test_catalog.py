from pathlib import Path
from skillpm import catalog


def _mk_skill(root: Path, name: str):
    d = root / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\n---\n")


def test_discover_lists_skill_dirs_sorted(tmp_path: Path):
    _mk_skill(tmp_path, "review-pr")
    _mk_skill(tmp_path, "debug")
    (tmp_path / "not-a-skill").mkdir()  # no SKILL.md -> ignored
    assert catalog.discover(tmp_path) == ["debug", "review-pr"]


def test_discover_missing_dir_returns_empty(tmp_path: Path):
    assert catalog.discover(tmp_path / "absent") == []
