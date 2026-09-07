#!/usr/bin/env python3
"""Stand the addon up in a project that has nothing else in it.

Everything else in this repository tests the addon inside the repository, which
is a project that has been imported hundreds of times, has a `.godot` cache full
of answers, and has a `test/` tree full of fixtures the addon does not ship. A
consumer has none of that. The failures this catches are the ones that only
happen the first time somebody drops the folder into their own game: a class
that resolves here because the cache already knows it, an autoload that boots
here because something else was parsed first, a path that exists because a test
made it.

So this copies `addons/GAS_Engine` and nothing else into a temporary project,
gives it the autoload a consumer would add, and runs it four ways: a cold
import with no cache, the editor, a headless script that uses the engine for
real, and an export.

    python tooling/distribution_check.py
    python tooling/distribution_check.py --out artifacts/parity/DISTRIBUTION.md

Exit code is 0 when every step a machine can run passed. A step that cannot run
here - an export with no templates installed - is reported as SKIPPED with the
reason, and does not pass.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

#: The permanently-authorised Godot on this machine. Overridable, because the
#: path is a fact about one workstation and this script is not.
GODOT = (
    r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine"
    r"\godot.windows.opt.tools.64.exe"
)

ADDON = "addons/GAS_Engine"

#: Where an export lands, named once because the preset and the directory
#: that has to exist before it are two spellings of one decision.
EXPORT_DIR = "exports"

#: What a consumer writes. The autoload is the one thing the addon cannot add
#: for itself, and the reason a first run fails when it is forgotten.
PROJECT_GODOT = """\
config_version=5

[application]

config/name="GAS_Engine consumer"
config/features=PackedStringArray("4.7")

[autoload]

GameplayCueManager="*res://addons/GAS_Engine/managers/gameplay_cue_manager.gd"
"""

#: The attribute set a consumer writes.
#:
#: AttributeSet is abstract on purpose - a game declares its own stats - so a
#: check that instantiated the base class would be checking something no
#: consumer ever does, and this is what found that out.
ATTRIBUTES = """\
@tool
class_name ConsumerAttributes extends AttributeSet

@export var health: AttributeData = AttributeData.new(100.0)


func _init() -> void:
\thealth = AttributeData.new(100.0)
"""

#: A game's first five minutes with the addon: make a character, give it an
#: attribute, put an effect on it, read the number back, and ask for both
#: targeting services. If any of that needs something only this repository
#: has, it fails here rather than in somebody's project.
#:
#: Built in `_init` and used in `_process`, because a component added to the
#: tree is not ready until the frame after - which is the first thing a
#: consumer trips over and the reason a check that used it immediately would
#: report a failure the addon does not have.
SMOKE = """\
extends SceneTree

var asc: AbilitySystemComponent = null
var frames: int = 0


func _init() -> void:
\tvar owner_node: Node = Node.new()
\tget_root().add_child(owner_node)

\tvar attributes: ConsumerAttributes = ConsumerAttributes.new()
\tasc = AbilitySystemComponent.new()
\tasc.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
\tasc.attribute_sets = [attributes] as Array[AttributeSet]
\tasc.share_attributes = true
\towner_node.add_child(asc)


func _process(_delta: float) -> bool:
\tframes += 1
\tif frames < 2:
\t\treturn false

\tvar effect: GameplayEffect = GameplayEffect.new()
\teffect.policy = GameplayEffect.DurationPolicy.INSTANT
\tvar modifier: GameplayEffectModifier = GameplayEffectModifier.new()
\tmodifier.attribute_name = &"health"
\tmodifier.operation = GameplayEffectModifier.Operation.ADD
\tvar flat: GameplayScalableFloat = GameplayScalableFloat.new()
\tflat.value = -30.0
\tmodifier.magnitude = GameplayScalableMagnitude.new()
\tmodifier.magnitude.value = flat
\teffect.modifiers = [modifier] as Array[GameplayEffectModifier]

\tasc.apply_gameplay_effect(effect)
\tvar left: float = asc.get_attribute_current(&"health")
\tprint("SMOKE health=", left)

\t# Both dimensions, because a consumer's game is one or the other and
\t# neither should need the addon to be told which.
\tprint("SMOKE 2d=", GameplayRaycastRequest2D.new() != null)
\tprint("SMOKE 3d=", GameplayRaycastRequest3D.new() != null)

\t# And with no Dialogic and no quest system in the project at all.
\tprint("SMOKE bridges_absent=", not ClassDB.class_exists("Dialogic"))

\tprint("SMOKE ok=", is_equal_approx(left, 70.0))
\treturn true
"""

#: The two export modes the phase names.
#:
#: `all_resources` is Godot's own default and ships the addon whole.
#: `scenes` ships what the preset names and its scene dependencies - and a
#: GDScript preload is not one of those on 4.7.2, measured, which is why a
#: consumer on that mode has to name the addon's own scenes. Both are run
#: rather than described, because a preset that does not export is a claim
#: nobody checked.
EXPORT_PRESETS = """\
[preset.0]

name="AllResources"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
export_files=PackedStringArray()
include_filter=""
exclude_filter=""
export_path="exports/AllResources.exe"
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

binary_format/embed_pck=false

[preset.1]

name="SelectedScenes"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="scenes"
export_files=PackedStringArray("res://main.tscn")
include_filter=""
exclude_filter=""
export_path="exports/SelectedScenes.exe"
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]

binary_format/embed_pck=false

"""

#: A scene for the selected-scenes preset to select.
MAIN_SCENE = """\
[gd_scene format=3]

[node name="Main" type="Node"]
"""

BAD = ("SCRIPT ERROR", "Parse Error", "Failed to load script", "Compile Error")


class Step:
    """One thing that was tried, and what came of it."""

    def __init__(self, name: str, verdict: str, detail: str) -> None:
        self.name = name
        self.verdict = verdict
        self.detail = detail

    def line(self) -> str:
        return "| %s | %s | %s |" % (self.name, self.verdict, self.detail)

    def passed(self) -> bool:
        return self.verdict == "PASS"


def run(where: Path, args: list[str], timeout: int = 300) -> tuple[int, str]:
    """Godot, with everything it said."""
    done = subprocess.run(
        [GODOT, "--headless", "--path", str(where), *args],
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
        timeout=timeout,
    )
    return done.returncode, (done.stdout or "") + (done.stderr or "")


def complaints(output: str) -> str:
    """The first thing Godot objected to, or nothing."""
    for line in output.splitlines():
        if any(mark in line for mark in BAD):
            return line.strip()
    return ""


def consumer_project(into: Path) -> None:
    """A project with the addon in it and nothing else."""
    shutil.copytree(ROOT / ADDON, into / ADDON)
    (into / "project.godot").write_text(PROJECT_GODOT, encoding="utf-8")
    (into / "consumer_attributes.gd").write_text(ATTRIBUTES, encoding="utf-8")
    (into / "smoke.gd").write_text(SMOKE, encoding="utf-8")
    (into / "export_presets.cfg").write_text(EXPORT_PRESETS, encoding="utf-8")
    (into / "main.tscn").write_text(MAIN_SCENE, encoding="utf-8")
    (into / EXPORT_DIR).mkdir()


def check(where: Path) -> list[Step]:
    steps: list[Step] = []

    _, imported = run(where, ["--import"])
    steps.append(
        Step(
            "cold import, no cache",
            "FAIL" if complaints(imported) else "PASS",
            complaints(imported) or "the addon parses with nothing cached",
        )
    )

    _, edited = run(where, ["--editor", "--quit"])
    steps.append(
        Step(
            "editor opens and closes",
            "FAIL" if complaints(edited) else "PASS",
            complaints(edited) or "the plugin loads in an editor session",
        )
    )

    # `--quit-after` and not only the script's own `quit()`: a runtime error
    # in a SceneTree script does not stop the main loop, so a smoke test that
    # relied on reaching its last line would hang for ever on the first thing
    # that went wrong - which is the one case it exists to report.
    _, ran = run(where, ["--quit-after", "60", "--script", "res://smoke.gd"], 180)
    worked = "SMOKE ok=true" in ran
    steps.append(
        Step(
            "headless, used for real",
            "PASS" if worked and not complaints(ran) else "FAIL",
            complaints(ran) or ("an effect applied and read back" if worked else ran[-200:]),
        )
    )
    for claim, said in (("2d=true", "2D targeting"), ("3d=true", "3D targeting")):
        steps.append(
            Step(
                said,
                "PASS" if "SMOKE " + claim in ran else "FAIL",
                "reachable from a project that has only the addon",
            )
        )
    steps.append(
        Step(
            "bridges absent",
            "PASS" if "SMOKE bridges_absent=true" in ran else "FAIL",
            "the addon runs with no Dialogic and no quest system present",
        )
    )

    for named, said in (
        ("AllResources", "export, all resources"),
        ("SelectedScenes", "export, selected scenes"),
    ):
        code, exported = run(
            where, ["--export-release", named, "%s/%s.exe" % (EXPORT_DIR, named)], 600
        )
        # The exact words Godot uses when the templates are absent. Matching
        # the bare word would call an ordinary export skipped for mentioning
        # a template path in passing, which is how a check reports a pass as
        # a gap.
        missing = 'no export template' in exported.lower()
        steps.append(
            Step(
                said,
                "SKIPPED" if missing else ("PASS" if code == 0 and not complaints(exported) else "FAIL"),
                "export templates are not installed here"
                if missing
                else (complaints(exported) or "the addon exports whole"),
            )
        )

    return steps


def report(steps: list[Step]) -> str:
    lines = [
        "# Distribution check",
        "",
        "The addon copied into a project that has nothing else in it, and run four",
        "ways. Written by `tooling/distribution_check.py`.",
        "",
        "| what was tried | verdict | detail |",
        "|---|---|---|",
    ]
    lines.extend(step.line() for step in steps)
    lines.append("")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", default="")
    parsed = parser.parse_args(argv)

    with tempfile.TemporaryDirectory(prefix="gas_engine_consumer_") as scratch:
        where = Path(scratch) / "project"
        where.mkdir()
        consumer_project(where)
        steps = check(where)

    written = report(steps)
    print(written)
    if parsed.out:
        out = ROOT / parsed.out
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(written, encoding="utf-8", newline="\n")
    return 0 if all(step.verdict != "FAIL" for step in steps) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
