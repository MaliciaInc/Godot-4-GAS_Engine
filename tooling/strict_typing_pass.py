#!/usr/bin/env python3
"""Prepare and tear down the strict-typing verification pass.

Godot's `debug/gdscript/warnings/exclude_addons` defaults to **true**, which
silently exempted every file under `addons/` from the eight warnings section 2.2
promotes to errors. The entire engine lives in `addons/GAS_Engine`, so the phase's
own typing gate was reporting green over code it had never looked at. That is
the blind-gate class this project exists to prevent.

Setting it to false is correct for our code and impossible for the project as a
whole: `addons/gut` is a vendored dependency pinned byte-identical by step 11.6,
it is not strictly typed, and under the strict setting it fails to parse - which
takes the whole test suite with it.

So the project runs in the permissive mode and is verified in a strict one:

    python tooling/strict_typing_pass.py enter
    <validate addons/GAS_Engine/** through the Godot MCP>
    python tooling/strict_typing_pass.py leave

`enter` writes `exclude_addons=false` and drops a `.gdignore` into `addons/gut`
so Godot skips the vendored dependency entirely. `leave` restores both. Neither
mode weakens a single warning: the difference is only which trees Godot applies
them to.

The pass covers `addons/GAS_Engine/**`. Test sources extend `GutTest` and cannot
be parsed while GUT is ignored, so they are checked in the permissive run and
by the four quality gates, which do not exclude them.
"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import project_invariants  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT_FILE = ROOT / project_invariants.PROJECT_FILE
GUT_IGNORE = ROOT / "addons" / "gut" / ".gdignore"

PERMISSIVE = project_invariants.EXCLUDE_ADDONS_LINE
STRICT = "gdscript/warnings/exclude_addons=false"

MARKER = "; STRICT-TYPING-PASS ACTIVE - run 'strict_typing_pass.py leave' to restore.\n"


def read_project() -> str:
    return PROJECT_FILE.read_text(encoding="utf-8")


def write_project(text: str) -> None:
    PROJECT_FILE.write_text(text, encoding="utf-8", newline="\n")


def enter() -> None:
    text = read_project()
    if MARKER in text:
        print("already in the strict pass")
        return
    if PERMISSIVE not in text:
        sys.exit("project.godot does not carry the expected " + PERMISSIVE + " line")
    write_project(MARKER + text.replace(PERMISSIVE, STRICT, 1))
    GUT_IGNORE.write_text(
        "# Written by tooling/strict_typing_pass.py. Godot skips this directory\n"
        "# while the strict pass runs, because GUT is a pinned vendored\n"
        "# dependency that is not strictly typed and must not be edited.\n",
        encoding="utf-8",
        newline="\n",
    )
    print("strict pass ACTIVE: addons excluded=false, addons/gut ignored")


def leave() -> None:
    text = read_project()
    if MARKER in text:
        text = text.replace(MARKER, "", 1)
    if STRICT in text:
        text = text.replace(STRICT, PERMISSIVE, 1)
    write_project(text)
    if GUT_IGNORE.exists():
        GUT_IGNORE.unlink()
    print("strict pass ENDED: project restored to the runnable configuration")


def status() -> None:
    text = read_project()
    active = MARKER in text or STRICT in text
    print("strict pass ACTIVE" if active else "strict pass inactive")
    print("addons/gut/.gdignore present:", GUT_IGNORE.exists())


COMMANDS = {"enter": enter, "leave": leave, "status": status}

if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
    sys.exit("usage: strict_typing_pass.py [enter|leave|status]")
COMMANDS[sys.argv[1]]()
