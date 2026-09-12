"""Ask the C++ runner for the ten scenarios and say where it wrote them."""
import os

import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "ue_reference_out.json")
TRAIL = os.path.join(HERE, "trail.txt")

with open(TRAIL, "w") as handle:
    world = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
    handle.write("world: %s%s" % (world, chr(10)))
    ok = unreal.ParityScenarios.run_all(world, OUT)
    handle.write("run_all: %s%s" % (ok, chr(10)))
    handle.flush()
    os.fsync(handle.fileno())
