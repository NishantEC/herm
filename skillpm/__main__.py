"""skillpm -- herm skill package manager engine. Runs on the VM."""
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
