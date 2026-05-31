from pathlib import Path
from skillpm import engine


def _mk_catalog_skill(root: Path, name: str):
    d = root / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\n---\n")


def _paths(tmp_path: Path) -> engine.Paths:
    return engine.Paths(
        catalog_dir=tmp_path / "catalog",
        skills_dir=tmp_path / "live",
        lockfile=tmp_path / "live" / "skills.toml",
    )


def test_load_or_seed_seeds_catalog_when_no_lockfile(tmp_path: Path):
    for n in ("debug", "review-pr"):
        _mk_catalog_skill(tmp_path / "catalog", n)
    p = _paths(tmp_path)
    entries = engine.load_or_seed(p)
    assert set(entries) == {"debug", "review-pr"}
    assert all(e.enabled and e.source == "catalog" for e in entries.values())
    assert p.lockfile.is_file()  # seed was persisted


def test_sync_materialises_enabled(tmp_path: Path):
    for n in ("debug", "review-pr"):
        _mk_catalog_skill(tmp_path / "catalog", n)
    p = _paths(tmp_path)
    engine.sync(p)
    assert (p.skills_dir / "debug" / "SKILL.md").is_file()


def test_toggle_disables_and_reconciles(tmp_path: Path):
    _mk_catalog_skill(tmp_path / "catalog", "debug")
    p = _paths(tmp_path)
    engine.sync(p)
    assert engine.toggle(p, "debug", False) is True
    assert not (p.skills_dir / "debug").exists()
    assert engine.toggle(p, "ghost", True) is False  # unknown skill


def test_list_rows_reports_state(tmp_path: Path):
    _mk_catalog_skill(tmp_path / "catalog", "debug")
    p = _paths(tmp_path)
    engine.sync(p)
    rows = engine.list_rows(p)
    assert rows == [("debug", "catalog", True, True)]

def test_load_or_seed_preserves_existing_noncatalog(tmp_path: Path):
    # catalog ships debug; the live dir already has debug + a private skill 'mine'
    _mk_catalog_skill(tmp_path / "catalog", "debug")
    _mk_catalog_skill(tmp_path / "live", "debug")
    _mk_catalog_skill(tmp_path / "live", "mine")
    p = _paths(tmp_path)
    entries = engine.load_or_seed(p)
    assert entries["debug"].source == "catalog"
    assert entries["mine"].source == "local" and entries["mine"].enabled
    # sync must KEEP the private skill, not delete it
    engine.sync(p)
    assert (p.skills_dir / "mine" / "SKILL.md").is_file()


def test_sync_reload_invokes_gateway(tmp_path: Path, monkeypatch):
    _mk_catalog_skill(tmp_path / "catalog", "debug")
    p = _paths(tmp_path)
    calls = []
    monkeypatch.setattr(engine.gateway, "reload", lambda: calls.append(1) or "stub")
    engine.sync(p, reload=True)
    assert calls == [1]
    engine.sync(p)  # default: no reload
    assert calls == [1]
