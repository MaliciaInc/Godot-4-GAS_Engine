#!/usr/bin/env python3
"""Check the facts about project.godot that nothing else can see.

Two hazards, both of which this project hit:

Opening the Godot editor rewrites project.godot. It normalises the file and
drops every `;` comment, which silently deleted `exclude_addons=true` and the
paragraph explaining why it is there. Nothing noticed until the strict-typing
pass refused to start, and had the pass not checked, the strict verification
would have applied to nothing and reported PASS.

The same rewrite drops any setting whose value equals the engine default, so
all nine warning lines are checked, not only the exclusion. Checking one of
them let the other eight - the typing contract itself - go missing under a
green gate.

The MCP servers inject their own autoload into project.godot on launch. Its
script is gitignored, so committing that line ships a project that declares an
autoload nobody who clones the repository has. Headless Godot initialises every
autoload before anything else, so the whole test suite fails to boot on a fresh
clone - and it fails nowhere else, which is what makes it worth a check.

Third, and found the same way: an autoload is parsed before Godot has scanned
the project for class_name declarations, so global class names do not resolve
inside it. `const Bucket = preload(".../gameplay_cue_pool_bucket.gd")` works;
`var b: GameplayCuePoolBucket` does not. It works on a machine that already has
.godot/global_script_class_cache.cfg, which is every machine that has opened
the project before, and fails on a fresh clone with

    Parser Error: Could not find type "GameplayCuePoolBucket" in the current scope

So this checks the whole parse-time closure of every autoload, not just the
autoload script: a preloaded file naming a global has the same effect.

Fourth, smaller and the same shape: Godot writes a `.gd.uid` beside each script
and resolves `uid://` references through it, so the two files are a pair and
either half can go missing. Moving a script leaves the .uid behind, tracked,
naming a path that no longer exists; adding a script without opening the editor
commits the script with no .uid at all, and every checkout then invents its own
id for it. Only the first half was checked, and the second half is how a test
script added from a shell reached main.

Fifth, and the one a consumer hits rather than us: a file-local `enum X` used as
a bare type annotation binds to any global named `X` instead - an autoload or a
`class_name`, either - in whatever project the addon is installed into. The
enum still wins for value access in the same statement, so the error reads as a
type mismatch against a name the file never mentions. The addon cannot see this
in its own project, because the collision only exists in a consumer's.

    python tooling/project_invariants.py [--project-root .]

Exit 0 when the project file is sound, 1 when it is not.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

from _gatelib import gate_io  # noqa: E402

PROJECT_FILE = "project.godot"

#: Godot excludes addons/** from warnings unless this is present, which would
#: exempt the whole engine. tooling/strict_typing_pass.py flips it and back.
EXCLUDE_ADDONS_LINE = "gdscript/warnings/exclude_addons=true"

#: The whole GDScript warning contract, not just the exclusion above.
#:
#: Godot writes project.godot back without any setting whose value equals the
#: engine default, so a rewrite drops these lines rather than changing them -
#: exactly the way it drops the comments. This was checking one of the nine and
#: calling the file sound: deleting `inference_on_variant=2` by hand and running
#: the check printed "project.godot is sound", which is the whole typing
#: contract of section 2 silently reduced to eight-ninths of itself with a green
#: gate over it.
#:
#: The list is declared here rather than read out of the file being checked. A
#: gate that takes its expectation from its subject agrees with whatever it
#: finds and can never fail.
STRICT_WARNING_LINES: tuple[str, ...] = (
    EXCLUDE_ADDONS_LINE,
    "gdscript/warnings/untyped_declaration=2",
    "gdscript/warnings/inferred_declaration=2",
    "gdscript/warnings/inference_on_variant=2",
    "gdscript/warnings/unsafe_property_access=2",
    "gdscript/warnings/unsafe_method_access=2",
    "gdscript/warnings/unsafe_cast=2",
    "gdscript/warnings/unsafe_call_argument=2",
    "gdscript/warnings/unsafe_void_return=2",
)

AUTOLOAD_SECTION = re.compile(r"^\[autoload\]$", re.MULTILINE)
SECTION = re.compile(r"^\[[^\]]+\]$", re.MULTILINE)
AUTOLOAD_ENTRY = re.compile(r'^(?P<name>\w+)\s*=\s*"\*?res://(?P<path>[^"]+)"', re.MULTILINE)


def autoload_block(text: str) -> str:
    """The body of [autoload], or empty when the project declares none."""
    opened = AUTOLOAD_SECTION.search(text)
    if opened is None:
        return ""
    rest = text[opened.end():]
    following = SECTION.search(rest)
    return rest if following is None else rest[: following.start()]


def tracked_files(root: Path) -> set[str] | None:
    """Every path git tracks, or None when this is not a git checkout."""
    try:
        done = subprocess.run(
            [gate_io.GIT_EXECUTABLE, "-C", str(root), gate_io.GIT_LIST_FILES],
            # Tracked only. gate_io.git_files also lists untracked-but-not-
            # ignored files, which is exactly the set that would hide this defect.
            capture_output=True, text=True, check=False,
        )
    except OSError:
        return None
    if done.returncode != 0:
        return None
    return {line.strip().replace("\\", "/") for line in done.stdout.splitlines() if line.strip()}



#: Anything under here declares the global classes an autoload must not rely on.
ADDON_ROOT = "addons/GAS_Engine"

PRELOADED = re.compile(r'preload\(\s*"(?P<path>res://[^"]+\.gd)"\s*\)')
DECLARES_CLASS = re.compile(r"^class_name\s+(?P<name>\w+)", re.MULTILINE)
#: A name the file binds itself. `const GameplayCueParams = preload(...)` is
#: the fix, not the defect, even though the constant and the global class
#: share a name - which is exactly what makes it read naturally.
PRELOAD_CONST = re.compile(r"^const\s+(?P<name>\w+)(?::\s*\w+)?\s*=\s*preload\(", re.MULTILINE)
COMMENT = re.compile(r"#.*$", re.MULTILINE)
STRING = re.compile(r'"[^"\n]*"' + r"|'[^'\n]*'")


def code_only(text: str) -> str:
    """The source with comments and string bodies removed.

    A class name inside a doc comment or a message is not a parse-time
    reference, and flagging one would teach a reader to ignore this check.
    """
    return COMMENT.sub("", STRING.sub('""', text))


def declared_classes(root: Path) -> dict[str, str]:
    """Every global class the addon declares, mapped to the file declaring it."""
    names: dict[str, str] = {}
    for path in sorted((root / ADDON_ROOT).rglob("*.gd")):
        found = DECLARES_CLASS.search(path.read_text(encoding="utf-8"))
        if found is not None:
            names[found.group("name")] = path.relative_to(root).as_posix()
    return names


def parse_closure(root: Path, start: str) -> list[str]:
    """`start` and every script it reaches through preload, transitively."""
    seen: list[str] = []
    pending = [start]
    while pending:
        relative = pending.pop()
        if relative in seen:
            continue
        path = root / relative
        if not path.is_file():
            continue
        seen.append(relative)
        text = path.read_text(encoding="utf-8")
        for match in PRELOADED.finditer(text):
            pending.append(match.group("path")[len("res://"):])
    return seen


def autoload_scripts(text: str) -> list[tuple[str, str]]:
    """Each autoload's name and the script it points at."""
    return [
        (entry.group("name"), entry.group("path"))
        for entry in AUTOLOAD_ENTRY.finditer(autoload_block(text))
    ]


def global_class_dependencies(root: Path, text: str) -> list[str]:
    """Autoload-closure files that name a global class instead of preloading it."""
    declared = declared_classes(root)
    found: list[str] = []
    for autoload, script in autoload_scripts(text):
        if not script.startswith(ADDON_ROOT):
            continue
        for relative in parse_closure(root, script):
            source = (root / relative).read_text(encoding="utf-8")
            own = DECLARES_CLASS.search(source)
            bound = {match.group("name") for match in PRELOAD_CONST.finditer(source)}
            body = code_only(source)
            for name, declared_in in sorted(declared.items()):
                if name in bound:
                    continue
                # A file's own class name resolves in a type annotation but
                # not as an identifier: `-> GameplayCueParams` parses where
                # `GameplayCueParams.new()` fails with "Identifier not
                # found". So for the file's own name only member access is a
                # defect, and that distinction is Godot's, observed on a
                # clean checkout rather than assumed.
                own_name = own is not None and name == own.group("name")
                pattern = r"\b%s\s*\." if own_name else r"\b%s\b"
                if re.search(pattern % re.escape(name), body) is None:
                    continue
                found.append(
                    "autoload %s reaches %s, which names the global class %s "
                    "(declared in %s) instead of preloading it. Godot parses "
                    "autoloads before the global class cache exists, so this "
                    "boots here and fails on a clean checkout."
                    % (autoload, relative, name, declared_in)
                )
    return found


#: Vendored and pinned byte-identical, so an orphan inside it came from upstream
#: and removing it would break the pin step 11.6 verifies.
VENDORED_PREFIX = "addons/gut/"

UID_SUFFIX = ".uid"
SCRIPT_SUFFIX = ".gd"


def orphaned_uid_files(root: Path) -> list[str]:
    """Tracked `.uid` files whose script is gone."""
    tracked = tracked_files(root)
    if tracked is None:
        return []
    found: list[str] = []
    for relative in sorted(tracked):
        if not relative.endswith(UID_SUFFIX) or relative.startswith(VENDORED_PREFIX):
            continue
        if relative.removesuffix(UID_SUFFIX) not in tracked:
            found.append(
                "%s has no script: Godot writes one of these beside each file and "
                "resolves uid:// through it, so this one names a path that is gone. "
                "Moving a script leaves it behind." % relative
            )
    return found


def scripts_without_uid(root: Path) -> list[str]:
    """Tracked scripts with no tracked `.uid` beside them."""
    tracked = tracked_files(root)
    if tracked is None:
        return []
    found: list[str] = []
    for relative in sorted(tracked):
        if not relative.endswith(SCRIPT_SUFFIX) or relative.startswith(VENDORED_PREFIX):
            continue
        if relative + UID_SUFFIX not in tracked:
            found.append(
                "%s has no tracked %s beside it. Godot writes one for every script "
                "and resolves uid:// through it, so a script committed without one is "
                "given a fresh id in every checkout and no two agree. Open the project "
                "once and commit the file it generates."
                % (relative, UID_SUFFIX)
            )
    return found


#: A type annotation position: after `:` or `->`, optionally inside Array[...].
#:
#: Horizontal whitespace only. `\s` crosses newlines, which made a `match x:`
#: whose next line is `Enum.VALUE:` read as an annotation - the enum name is
#: there, but as a branch label, and qualifying it would be wrong.
BARE_ANNOTATION = r"(?::|->)[^\S\n]*(?:Array\[)?[^\S\n]*%s\b"

ENUM_DECLARATION = re.compile(r"^enum\s+(\w+)\s*\{", re.MULTILINE)


def shadowable_enum_annotations(root: Path) -> list[str]:
    """Addon enums used as a bare type annotation in the file declaring them.

    Qualifying costs nothing and is already the convention elsewhere in the
    addon; leaving one bare makes the whole file - and everything that depends
    on it - fail to parse in any project that happens to declare a global of
    that name. The names at stake are ordinary words like State, Status, Type
    and Mode, so this is not a contract a consumer could be asked to honour.
    """
    found: list[str] = []
    for path in sorted((root / ADDON_ROOT).rglob("*.gd")):
        text = path.read_text(encoding="utf-8")
        body = code_only(text)
        relative = path.relative_to(root).as_posix()
        for match in ENUM_DECLARATION.finditer(body):
            name = match.group("name") if "name" in match.groupdict() else match.group(1)
            uses = re.findall(BARE_ANNOTATION % re.escape(name), body)
            if not uses:
                continue
            owner = DECLARES_CLASS.search(body)
            qualified = (
                "%s.%s" % (owner.group("name"), name) if owner is not None
                else "a `const Alias = preload(...)` of this file, then Alias.%s" % name
            )
            found.append(
                "%s uses its own `enum %s` as a bare type annotation %d time(s). "
                "In a project that declares any global named %s - an autoload or a "
                "class_name - the annotation binds to that global instead and this "
                "file stops parsing, taking every dependent script with it. Write "
                "%s." % (relative, name, len(uses), name, qualified)
            )
    return found


def problems(root: Path) -> list[str]:
    path = root / PROJECT_FILE
    if not path.is_file():
        return ["%s not found under %s" % (PROJECT_FILE, root)]

    text = path.read_text(encoding="utf-8")
    found: list[str] = []

    for required in STRICT_WARNING_LINES:
        if required not in text:
            found.append(
                "%s is missing %r. Opening the Godot editor - or running the "
                "project - rewrites this file, dropping its comments and every "
                "setting that matches an engine default; restore it with "
                "`git checkout -- %s` before committing."
                % (PROJECT_FILE, required, PROJECT_FILE)
            )

    tracked = tracked_files(root)
    for entry in AUTOLOAD_ENTRY.finditer(autoload_block(text)):
        relative = entry.group("path")
        if not (root / relative).is_file():
            found.append(
                "autoload %s points at %s, which does not exist"
                % (entry.group("name"), relative)
            )
        elif tracked is not None and relative not in tracked:
            found.append(
                "autoload %s points at %s, which git does not track. A clean "
                "checkout would declare an autoload it does not have, and "
                "headless Godot initialises every autoload before the suite runs."
                % (entry.group("name"), relative)
            )

    found.extend(global_class_dependencies(root, text))
    found.extend(orphaned_uid_files(root))
    found.extend(scripts_without_uid(root))
    found.extend(shadowable_enum_annotations(root))
    return found


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(gate_io.PROJECT_ROOT_FLAG, default=".", type=Path)
    args = parser.parse_args(argv)
    root = args.project_root.resolve()

    found = problems(root)
    for item in found:
        print("project-invariants: ERROR: " + item, file=sys.stderr)
    if not found:
        print("project-invariants: %s is sound" % PROJECT_FILE)
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
