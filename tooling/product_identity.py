#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

PRODUCT = "GAS_Engine"
ADDON_ROOT = "addons/GAS_Engine"
PLUGIN_CFG = ADDON_ROOT + "/plugin.cfg"
PLUGIN_SCRIPT = ADDON_ROOT + "/gas_engine_plugin.gd"
CUE_MANAGER = ADDON_ROOT + "/managers/gameplay_cue_manager.gd"
PROJECT_SETTINGS = ADDON_ROOT + "/utilities/project_settings.gd"

FORBIDDEN = (
    "Arhalies" + "_GAS",
    "Arhalies" + " GAS",
    "Arhalies" + "-GAS",
    "Godot" + "GAS",
    "godot" + "_gas",
    "addons/" + "Godot" + "GAS",
    "res://addons/" + "Godot" + "GAS",
    "res://" + "godot" + "_gas",
)

TEXT_SUFFIXES = {
    ".gd", ".tscn", ".tres", ".cfg", ".godot", ".py", ".ps1",
    ".json", ".md", ".txt", ".svg", ".import",
}

SKIP_PREFIXES = (
    "addons/gut/",
    "artifacts/gates/",
)

LEGACY_SECTION_START = "## Legacy MIT source notice"
LEGACY_SECTION_END = "## GUT (Godot Unit Test)"


def tracked_files(root: Path) -> list[str]:
    done = subprocess.run(
        ["git", "-C", str(root), "ls-files"],
        capture_output=True,
        text=True,
        check=False,
    )
    if done.returncode != 0:
        raise RuntimeError(done.stderr.strip() or "git ls-files failed")
    return [line.strip().replace("\\", "/") for line in done.stdout.splitlines() if line.strip()]


def third_party_legacy_lines(text: str) -> set[int]:
    lines = text.splitlines()
    inside = False
    allowed: set[int] = set()
    for index, line in enumerate(lines, start=1):
        if line.strip() == LEGACY_SECTION_START:
            inside = True
        if inside:
            allowed.add(index)
        if line.strip() == LEGACY_SECTION_END:
            inside = False
            allowed.discard(index)
    return allowed


def occurrence_allowed(path: str, line_number: int, line: str) -> bool:
    if path == "THIRD_PARTY.md":
        text = Path(path).read_text(encoding="utf-8") if Path(path).is_file() else ""
        return line_number in third_party_legacy_lines(text)
    if path == PROJECT_SETTINGS and "LEGACY_" in line:
        return True
    if path == "tooling/gates/tests/test_product_identity.py":
        return True
    return False


def text_problems(root: Path, files: list[str]) -> list[str]:
    found: list[str] = []
    for relative in files:
        if relative == "tooling/product_identity.py":
            continue
        if relative.startswith(SKIP_PREFIXES):
            continue
        path = root / relative
        if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in {"LICENSE", "VERSION"}:
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(lines, start=1):
            for token in FORBIDDEN:
                if token not in line:
                    continue
                if occurrence_allowed(relative, line_number, line):
                    continue
                found.append(f"{relative}:{line_number}: forbidden identity {token!r}")
    return found


def path_problems(files: list[str]) -> list[str]:
    found: list[str] = []
    for relative in files:
        if relative.startswith(SKIP_PREFIXES):
            continue
        for token in FORBIDDEN:
            if token in relative:
                found.append(f"{relative}: forbidden identity in tracked path {token!r}")
    return found


def authority_problems(root: Path) -> list[str]:
    found: list[str] = []

    required_files = (
        PLUGIN_CFG,
        PLUGIN_SCRIPT,
        CUE_MANAGER,
        "addons/GAS_Engine/editor/gas_engine_dashboard.tscn",
        "gas_engine/gameplay_tags.gd",
    )
    for relative in required_files:
        if not (root / relative).is_file():
            found.append(f"missing canonical file: {relative}")

    project = (root / "project.godot").read_text(encoding="utf-8")
    required_project_lines = (
        'config/name="GAS_Engine"',
        'GameplayCueManager="*res://addons/GAS_Engine/managers/gameplay_cue_manager.gd"',
        '"res://addons/GAS_Engine/plugin.cfg"',
    )
    for line in required_project_lines:
        if line not in project:
            found.append(f"project.godot missing authority: {line}")

    plugin = (root / PLUGIN_CFG).read_text(encoding="utf-8")
    required_plugin_lines = (
        'name="GAS_Engine"',
        'author="MaliciaInc"',
        'script="gas_engine_plugin.gd"',
        'version="3.0.0"',
    )
    for line in required_plugin_lines:
        if line not in plugin:
            found.append(f"{PLUGIN_CFG} missing authority: {line}")

    return found


def problems(root: Path) -> list[str]:
    files = tracked_files(root)
    return path_problems(files) + text_problems(root, files) + authority_problems(root)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path("."))
    args = parser.parse_args(argv)
    root = args.project_root.resolve()

    found = problems(root)
    for item in found:
        print("product-identity: ERROR: " + item, file=sys.stderr)
    if found:
        return 1
    print("product-identity: GAS_Engine identity is canonical")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
