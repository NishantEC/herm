# herm skills package manager — Implementation Plan (Phase 1: Backbone)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the boot-only `rsync` skill bundle with a durable, reconcilable skill set the owner can `list`/`enable`/`disable`/`sync` at runtime — the backbone the package manager builds on.

**Architecture:** A small Python engine (`skillpm`) ships to `/opt/herm/skillpm/` and runs under Hermes' venv interpreter. It owns a TOML lockfile and reconciles `~/.hermes/skills/herm/` to it. `cloud-init/scripts/07-seed-skills.sh` becomes a thin `skillpm sync` caller (back-compat: no lockfile ⇒ seed the catalog). A thin bash wrapper `cli/commands/skills.sh` runs the engine on the VM over `tailscale ssh`.

**Tech Stack:** Python 3 (stdlib + `pyyaml` already in the Hermes venv; `tomllib` for reads, hand-rolled emit for writes), Bash, `pytest`, `bats`.

**Scope:** This plan is **Phase 1 of 4** from `docs/superpowers/specs/2026-05-31-herm-skills-package-manager-design.md`. Phase 1 delivers the lockfile + engine + reconcile + `list/enable/disable/sync` over the **catalog** source only, with the lockfile living **on the VM** (`~/.hermes/skills/herm/skills.toml`). Phases 2–4 (external sources + laptop-side lockfile, `requires:` dependency auto-resolve, registry) are summarised at the end and each get their own plan. This split is the spec's own "Suggested implementation phases."

---

## File structure (Phase 1)

| File | Responsibility |
|---|---|
| `skillpm/__init__.py` | Package marker. |
| `skillpm/lockfile.py` | `SkillEntry` model; `load`/`dumps`/`save` for `skills.toml`. |
| `skillpm/catalog.py` | Discover catalog skills under `/opt/herm/skills`. |
| `skillpm/reconcile.py` | Diff lockfile-desired vs on-disk; install/remove within the `herm/` namespace. |
| `skillpm/engine.py` | `Paths` context, `load_or_seed`, `sync`, `list_rows`, `toggle`. |
| `skillpm/__main__.py` | `python -m skillpm {list,sync,enable,disable}` dispatch. |
| `cloud-init/scripts/07-seed-skills.sh` | **Rewrite:** call `skillpm sync` instead of `rsync`. |
| `cli/commands/up.sh` | **Modify:** ship the `skillpm/` tree to `/opt/herm/skillpm/`. |
| `cli/commands/skills.sh` | **New:** `herm skills` bash wrapper. |
| `bin/herm` | **Modify:** register `skills` + help group. |
| `tests/skillpm/test_*.py` | `pytest` for engine modules. |
| `tests/cli/test_skills.bats` | `bats` for the wrapper. |
| `.github/workflows/ci.yml` | **Modify:** add a `pytest` job. |
| `README.md`, `CHANGELOG.md`, `docs/skills.md` | **Modify:** document the new commands. |

---

## Task 1: Lockfile module

**Files:**

- Create: `skillpm/__init__.py`
- Create: `skillpm/lockfile.py`
- Test: `tests/skillpm/test_lockfile.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/skillpm/test_lockfile.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=. pytest tests/skillpm/test_lockfile.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'skillpm'`.

- [ ] **Step 3: Write minimal implementation**

```python
# skillpm/__init__.py
"""herm skill package manager engine."""
```

```python
# skillpm/lockfile.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `PYTHONPATH=. pytest tests/skillpm/test_lockfile.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add skillpm/__init__.py skillpm/lockfile.py tests/skillpm/test_lockfile.py
git commit -m "feat(skillpm): lockfile read/emit for skills.toml"
```

---

## Task 2: Catalog discovery

**Files:**

- Create: `skillpm/catalog.py`
- Test: `tests/skillpm/test_catalog.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/skillpm/test_catalog.py
from pathlib import Path
from skillpm import catalog


def _mk_skill(root: Path, name: str):
    d = root / name
    d.mkdir(parents=True)
    (d / "SKILL.md").write_text(f"---\nname: {name}\n---\n")


def test_discover_lists_skill_dirs_sorted(tmp_path: Path):
    _mk_skill(tmp_path, "review-pr")
    _mk_skill(tmp_path, "debug")
    (tmp_path / "not-a-skill").mkdir()  # no SKILL.md → ignored
    assert catalog.discover(tmp_path) == ["debug", "review-pr"]


def test_discover_missing_dir_returns_empty(tmp_path: Path):
    assert catalog.discover(tmp_path / "absent") == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=. pytest tests/skillpm/test_catalog.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'skillpm.catalog'`.

- [ ] **Step 3: Write minimal implementation**

```python
# skillpm/catalog.py
"""Discover skills shipped in this repo's catalog (on the VM: /opt/herm/skills)."""
from __future__ import annotations

from pathlib import Path


def discover(catalog_dir: Path) -> list[str]:
    if not catalog_dir.is_dir():
        return []
    return sorted(p.parent.name for p in catalog_dir.glob("*/SKILL.md"))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `PYTHONPATH=. pytest tests/skillpm/test_catalog.py -v`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add skillpm/catalog.py tests/skillpm/test_catalog.py
git commit -m "feat(skillpm): catalog skill discovery"
```

---

## Task 3: Reconciler

**Files:**

- Create: `skillpm/reconcile.py`
- Test: `tests/skillpm/test_reconcile.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/skillpm/test_reconcile.py
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
        "review-pr": SkillEntry(name="review-pr", enabled=False),  # disabled → not installed
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
    (live / "keepme.txt").write_text("not a skill")  # no SKILL.md → untouched
    reconcile.reconcile({}, catalog, live)
    assert (live / "keepme.txt").is_file()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=. pytest tests/skillpm/test_reconcile.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'skillpm.reconcile'`.

- [ ] **Step 3: Write minimal implementation**

```python
# skillpm/reconcile.py
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
            continue  # non-catalog source — later phases
        shutil.copytree(src, skills_dir / name, dirs_exist_ok=True)
        installed.append(name)
    for name in sorted(have - want):
        shutil.rmtree(skills_dir / name)
        removed.append(name)
    return {"installed": installed, "removed": removed, "kept": sorted(want & have)}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `PYTHONPATH=. pytest tests/skillpm/test_reconcile.py -v`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add skillpm/reconcile.py tests/skillpm/test_reconcile.py
git commit -m "feat(skillpm): namespace-safe reconcile"
```

---

## Task 4: Engine + CLI entrypoint (with back-compat seed)

**Files:**

- Create: `skillpm/engine.py`
- Create: `skillpm/__main__.py`
- Test: `tests/skillpm/test_engine.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/skillpm/test_engine.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `PYTHONPATH=. pytest tests/skillpm/test_engine.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'skillpm.engine'`.

- [ ] **Step 3: Write minimal implementation**

```python
# skillpm/engine.py
"""Engine context + operations shared by the boot reconciler and the CLI."""
from __future__ import annotations

import dataclasses
import os
from pathlib import Path

from . import catalog, lockfile, reconcile


@dataclasses.dataclass
class Paths:
    catalog_dir: Path
    skills_dir: Path
    lockfile: Path

    @classmethod
    def from_env(cls) -> "Paths":
        skills_dir = Path(
            os.environ.get("SKILLPM_HOME", str(Path.home() / ".hermes" / "skills" / "herm"))
        )
        catalog_dir = Path(os.environ.get("SKILLPM_CATALOG", "/opt/herm/skills"))
        return cls(catalog_dir=catalog_dir, skills_dir=skills_dir, lockfile=skills_dir / "skills.toml")


def load_or_seed(paths: Paths) -> dict[str, lockfile.SkillEntry]:
    entries = lockfile.load(paths.lockfile)
    if not entries:
        # Back-compat: no lockfile → seed all catalog skills enabled (prior behavior).
        entries = {n: lockfile.SkillEntry(name=n) for n in catalog.discover(paths.catalog_dir)}
        lockfile.save(paths.lockfile, entries)
    return entries


def sync(paths: Paths) -> dict:
    return reconcile.reconcile(load_or_seed(paths), paths.catalog_dir, paths.skills_dir)


def list_rows(paths: Paths) -> list[tuple[str, str, bool, bool]]:
    entries = load_or_seed(paths)
    live = reconcile.actual(paths.skills_dir)
    return [(n, e.source, e.enabled, n in live) for n, e in sorted(entries.items())]


def toggle(paths: Paths, name: str, enabled: bool) -> bool:
    entries = load_or_seed(paths)
    if name not in entries:
        return False
    entries[name].enabled = enabled
    lockfile.save(paths.lockfile, entries)
    reconcile.reconcile(entries, paths.catalog_dir, paths.skills_dir)
    return True
```

```python
# skillpm/__main__.py
"""skillpm — herm skill package manager engine. Runs on the VM."""
from __future__ import annotations

import sys

from . import engine

USAGE = "usage: skillpm {list | sync | enable <name> | disable <name>}"


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print(USAGE, file=sys.stderr)
        return 2
    paths = engine.Paths.from_env()
    cmd, rest = argv[0], argv[1:]

    if cmd == "sync":
        s = engine.sync(paths)
        print(f"[skillpm] sync: +{len(s['installed'])} -{len(s['removed'])} ={len(s['kept'])}")
        for n in s["installed"]:
            print(f"  + {n}")
        for n in s["removed"]:
            print(f"  - {n}")
        return 0

    if cmd == "list":
        for name, source, enabled, live in engine.list_rows(paths):
            state = "enabled" if enabled else "disabled"
            print(f"{name:<20} {source:<8} {state:<9} {'live' if live else 'absent'}")
        return 0

    if cmd in ("enable", "disable"):
        if not rest:
            print(USAGE, file=sys.stderr)
            return 2
        if not engine.toggle(paths, rest[0], cmd == "enable"):
            print(f"[skillpm] unknown skill: {rest[0]}", file=sys.stderr)
            return 2
        print(f"[skillpm] {rest[0]} {cmd}d")
        return 0

    print(f"[skillpm] unknown command: {cmd}\n{USAGE}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `PYTHONPATH=. pytest tests/skillpm -v`
Expected: PASS (all tests across the four modules).
Also smoke-test the CLI:
Run: `SKILLPM_CATALOG=$PWD/skills SKILLPM_HOME=$(mktemp -d) PYTHONPATH=. python -m skillpm list`
Expected: one row per repo skill, `catalog enabled live`.

- [ ] **Step 5: Commit**

```bash
git add skillpm/engine.py skillpm/__main__.py tests/skillpm/test_engine.py
git commit -m "feat(skillpm): engine ops + python -m skillpm CLI with back-compat seed"
```

---

## Task 5: Rewrite the boot reconciler

**Files:**

- Modify: `cloud-init/scripts/07-seed-skills.sh` (full replace)

- [ ] **Step 1: Replace the script body**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# Reconcile the herm skill set to the declarative lockfile via the skillpm engine.
# Replaces the old blind rsync of /opt/herm/skills. Back-compat: on first boot
# (no lockfile) skillpm seeds every catalog skill enabled — matching prior behavior.
#
# Idempotent. Operates only within ~/.hermes/skills/herm/; user-authored skills
# in sibling namespaces are untouched.

set -euo pipefail

PY=/home/herm/.hermes/hermes-agent/venv/bin/python
SKILLPM=/opt/herm/skillpm

if [[ ! -x $PY ]]; then
  echo "[07-seed-skills] no Hermes venv python — skipping"
  exit 0
fi
if [[ ! -d $SKILLPM ]]; then
  echo "[07-seed-skills] no skillpm shipped — skipping"
  exit 0
fi

sudo -u herm \
  PYTHONPATH=/opt/herm \
  SKILLPM_CATALOG=/opt/herm/skills \
  "$PY" -m skillpm sync
```

- [ ] **Step 2: Lint**

Run: `shellcheck cloud-init/scripts/07-seed-skills.sh`
Expected: no warnings.

- [ ] **Step 3: Commit**

```bash
git add cloud-init/scripts/07-seed-skills.sh
git commit -m "feat(07-seed-skills): reconcile via skillpm instead of blind rsync"
```

---

## Task 6: Ship `skillpm/` to the VM via the startup-script renderer

**Files:**

- Modify: `cli/commands/up.sh` (`herm::__render_startup_script`)

- [ ] **Step 1: Add the skillpm dir to the preamble `mkdir`**

In the `__HERM_PREAMBLE__` heredoc, change the `mkdir -p` line (currently `mkdir -p /opt/herm/scripts /opt/herm/skills /opt/herm/config /etc/systemd/system`) to also create the engine dir:

```bash
mkdir -p /opt/herm/scripts /opt/herm/skills /opt/herm/skillpm /opt/herm/config /etc/systemd/system
```

- [ ] **Step 2: Add a skillpm-tree inlining block**

Immediately after the existing skills-tree `if [[ -d $skills_dir ]]; then … fi` block, add an analogous block (and declare `local skillpm_dir="$HERM_REPO_ROOT/skillpm"` next to the other `local …_dir` declarations at the top of the function):

```bash
  # Inline the skillpm engine (Python package) to /opt/herm/skillpm/, mirroring
  # the skills-tree inlining above. Only *.py files are shipped.
  if [[ -d $skillpm_dir ]]; then
    local pm_file pm_rel pm_dest
    while IFS= read -r pm_file; do
      pm_rel="${pm_file#"$skillpm_dir"/}"
      pm_dest="/opt/herm/skillpm/$pm_rel"
      printf "\nmkdir -p %q\n" "$(dirname "$pm_dest")"
      printf "cat > %q <<'__HERM_PM_FILE__'\n" "$pm_dest"
      cat "$pm_file"
      printf "__HERM_PM_FILE__\nchmod 0644 %q\n" "$pm_dest"
    done < <(find "$skillpm_dir" -type f -name '*.py')
  fi
```

- [ ] **Step 3: Lint**

Run: `shellcheck cli/commands/up.sh cli/lib.sh bin/herm`
Expected: no warnings.

- [ ] **Step 4: Verify the rendered script references skillpm**

Run: `HERM_CONFIG_PATH=examples/config.toml.example bash -c 'source cli/lib.sh; source cli/commands/up.sh; herm::__render_startup_script' | grep -c '/opt/herm/skillpm/'`
Expected: a non-zero count (one `mkdir`+`cat` pair per `skillpm/*.py`, plus the preamble `mkdir`).

- [ ] **Step 5: Commit**

```bash
git add cli/commands/up.sh
git commit -m "feat(up): ship skillpm engine to /opt/herm/skillpm on boot"
```

---

## Task 7: `herm skills` bash wrapper + dispatch

**Files:**

- Create: `cli/commands/skills.sh`
- Modify: `bin/herm` (case-list + help)
- Test: `tests/cli/test_skills.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/cli/test_skills.bats
setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(mktemp -d)"
  # Fake config so herm::read_config finds a hostname.
  mkdir -p "$TMP/cfg"
  printf '[tailscale]\nhostname = "herm-vm"\n' > "$TMP/cfg/config.toml"
  export HERM_CONFIG_PATH="$TMP/cfg/config.toml"
  # Stub tailscale: record the args it was called with.
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/tailscale" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$TMP/tailscale.args"
EOF
  chmod +x "$TMP/bin/tailscale"
  export PATH="$TMP/bin:$PATH"
}

teardown() { rm -rf "$TMP"; }

@test "herm skills list invokes skillpm list over tailscale ssh" {
  run "$REPO/bin/herm" skills list
  [ "$status" -eq 0 ]
  grep -q 'ssh herm@herm-vm' "$TMP/tailscale.args"
  grep -q -- '-m skillpm list' "$TMP/tailscale.args"
}

@test "herm skills enable requires a name" {
  run "$REPO/bin/herm" skills enable
  [ "$status" -ne 0 ]
}

@test "herm skills rejects unknown subcommand" {
  run "$REPO/bin/herm" skills frobnicate
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/cli/test_skills.bats`
Expected: FAIL — `unknown command: skills` (not yet registered).

- [ ] **Step 3: Create the wrapper**

```bash
# cli/commands/skills.sh
# shellcheck shell=bash
# herm skills — manage the agent's skill set on the VM via the skillpm engine.
# Thin wrapper: transports subcommands to /opt/herm/skillpm over Tailscale SSH.

herm::__skills_run() {
  local hostname
  hostname="$(herm::read_config "$HERM_CONFIG_PATH" tailscale hostname)"
  herm::require_cmd tailscale
  tailscale ssh "herm@$hostname" -- \
    env PYTHONPATH=/opt/herm SKILLPM_CATALOG=/opt/herm/skills \
    /home/herm/.hermes/hermes-agent/venv/bin/python -m skillpm "$@"
}

herm::cmd::skills() {
  if [[ ! -f $HERM_CONFIG_PATH ]]; then
    herm::die "no config at $HERM_CONFIG_PATH — run 'herm init' first"
  fi
  local sub="${1:-list}"
  shift || true
  case "$sub" in
    list|sync)
      herm::__skills_run "$sub"
      ;;
    enable|disable)
      [[ -n ${1:-} ]] || herm::die "usage: herm skills $sub <name>"
      herm::__skills_run "$sub" "$1"
      ;;
    help|-h|--help)
      cat <<'EOF'
usage: herm skills <subcommand>

  list                 show installed skills and enabled/live state
  sync                 reconcile the VM's skill set to the lockfile
  enable <name>        enable a skill and reconcile
  disable <name>       disable a skill and reconcile
EOF
      ;;
    *)
      herm::die "unknown subcommand: $sub (try: herm skills help)"
      ;;
  esac
}
```

- [ ] **Step 4: Register in `bin/herm`**

Add `skills` to the dispatch case-list (the line beginning `init|up|down|…`):

```bash
  init|up|down|nuke|status|ssh|login|open|qr|rotate|upgrade|backup|restore|logs|console|skills)
```

And add a help group to the `usage()` heredoc, after the `AUTH` block:

```text
SKILLS
  skills <subcommand>   Manage the agent's skills (list | sync | enable | disable)
```

- [ ] **Step 5: Run tests + lint to verify they pass**

Run: `bats tests/cli/test_skills.bats && shellcheck bin/herm cli/commands/skills.sh`
Expected: PASS (3 tests), no shellcheck warnings.

- [ ] **Step 6: Commit**

```bash
git add cli/commands/skills.sh bin/herm tests/cli/test_skills.bats
git commit -m "feat(cli): herm skills wrapper (list/sync/enable/disable)"
```

---

## Task 8: CI — add a pytest job

**Files:**

- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add a `pytest` job**

Append this job under `jobs:` (mirrors the existing `bats` job):

```yaml
  pytest:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"
      - run: pip install pytest
      - run: PYTHONPATH=. pytest tests/skillpm -v
```

- [ ] **Step 2: Verify locally**

Run: `PYTHONPATH=. pytest tests/skillpm -v`
Expected: PASS (all engine tests).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run skillpm pytest suite"
```

---

## Task 9: Documentation

**Files:**

- Modify: `docs/skills.md` (add the `herm skills` section)
- Modify: `README.md` (Skills section — mention the CLI)
- Modify: `CHANGELOG.md` (`[Unreleased]`)

- [ ] **Step 1: Add a "Managing skills with `herm skills`" section to `docs/skills.md`**

After the "Adding your own skill" section, add:

```markdown
## Managing skills with `herm skills`

Skills are now reconciled from a lockfile (`~/.hermes/skills/herm/skills.toml`)
by the `skillpm` engine, not blind-copied. Manage them from your laptop:

| Command | Effect |
|---|---|
| `herm skills list` | Show each skill, its source, and enabled/live state. |
| `herm skills sync` | Reconcile the VM's `herm/` skills to the lockfile. |
| `herm skills enable <name>` | Enable a skill and reconcile. |
| `herm skills disable <name>` | Disable a skill (removes it from the live set) and reconcile. |

On first boot (or an upgrade from the old seeder) with no lockfile, `skillpm`
seeds every catalog skill enabled — identical to the previous behavior.
```

- [ ] **Step 2: Update the README Skills section**

In `README.md`, in the `## Skills` section, after the skills table, add:

```markdown
Manage the active set at runtime from your laptop with `herm skills {list|sync|enable|disable}` — skills are reconciled from a lockfile, not blind-copied. See [`docs/skills.md`](docs/skills.md).
```

- [ ] **Step 3: Add a CHANGELOG entry**

Under `## [Unreleased]` → `### Added` in `CHANGELOG.md`:

```markdown
- **`herm skills` (phase 1).** A `skillpm` engine on the VM reconciles `~/.hermes/skills/herm/` from a lockfile (`skills.toml`); `cloud-init/scripts/07-seed-skills.sh` now calls `skillpm sync` instead of `rsync`. New `herm skills list|sync|enable|disable`. Back-compat: no lockfile seeds the catalog, matching prior behavior.
```

- [ ] **Step 4: Lint docs**

Run: `npx -y markdownlint-cli2 README.md CHANGELOG.md docs/skills.md`
Expected: no errors (or only pre-existing repo-config-permitted ones).

- [ ] **Step 5: Commit**

```bash
git add docs/skills.md README.md CHANGELOG.md
git commit -m "docs: herm skills runtime management (phase 1)"
```

---

## Phase 1 acceptance

- `pytest tests/skillpm` and `bats tests/cli` green; `shellcheck` clean.
- On a `herm up --replace-vm`, the VM boots with the six catalog skills (no lockfile ⇒ seeded), identical to today.
- `herm skills disable watch-repo` removes it from `~/.hermes/skills/herm/` and persists across reboot (lockfile on the persistent disk); `herm skills enable watch-repo` restores it.
- `herm skills list` shows source/enabled/live per skill.

---

## Roadmap: Phases 2–4 (separate plans)

Each lands as its own `docs/superpowers/plans/` file with the same TDD structure.

- **Phase 2 — Sources + laptop lockfile.** `add`/`remove`; resolve `catalog | local | git`; pin git to a full SHA at add-time; vendor `local` skills into `~/.config/herm/skills/<name>/`; move the authoritative lockfile to `~/.config/herm/skills.toml` with push/pull around the VM engine (the hybrid model). `skillpm` gains `add`/`remove` + a fetch module; `reconcile` learns git/local materialisation.
- **Phase 3 — Dependency auto-resolve.** Add the optional `requires:` frontmatter field; transitive sibling-skill resolution (cycle-guarded); install missing fleet CLIs via the `10-install-cli-fleet.sh` map; warn (don't auto-edit) for MCP servers / toolsets; consent prompt on external `add`; `tools: []` default for foreign skills. `herm skills info`.
- **Phase 4 — Registry.** `registry.toml` index (name → git source) shipped in-repo and overridable via `[skills] registry` in `config.toml`; `herm skills add <name>` registry fallback; `herm skills search`.

---

## Self-review (done)

- **Spec coverage:** Phase 1 covers the spec's §Architecture (engine + wrapper + lockfile), §Reconciliation, §Boot integration + back-compat, and the `list/sync/enable/disable` slice of §Command surface. External sources, `requires:`, registry, and consent are explicitly deferred to Phases 2–4 (mapped above) — no silent gaps.
- **Placeholder scan:** none — every code/step is concrete.
- **Type consistency:** `SkillEntry`, `Paths`, `lockfile.load/dumps/save`, `catalog.discover`, `reconcile.{desired,actual,reconcile}`, `engine.{load_or_seed,sync,list_rows,toggle}` are used identically across tasks and tests.
