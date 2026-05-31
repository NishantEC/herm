from pathlib import Path
from skillpm import lockfile
from skillpm.lockfile import SkillEntry


def test_roundtrip_preserves_entries(tmp_path: Path):
    p = tmp_path / "skills.toml"
    entries = {
        "debug": SkillEntry(name="debug", source="catalog", enabled=True),
        "pr-triage": SkillEntry(
            name="pr-triage", source="git", enabled=False,
            url="https://github.com/u/r", ref="abc123", subdir="skills/pr-triage",
        ),
    }
    lockfile.save(p, entries)
    back = lockfile.load(p)
    assert back == entries


def test_load_missing_file_returns_empty(tmp_path: Path):
    assert lockfile.load(tmp_path / "nope.toml") == {}


def test_emit_is_deterministic_and_sorted(tmp_path: Path):
    entries = {
        "b": SkillEntry(name="b"),
        "a": SkillEntry(name="a"),
    }
    text = lockfile.dumps(entries)
    assert text.index("[skills.a]") < text.index("[skills.b]")
