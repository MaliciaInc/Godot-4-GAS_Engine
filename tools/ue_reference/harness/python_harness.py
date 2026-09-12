"""The half of the reference harness that needs no C++ compile.

Everything a scenario is built from is reflected and reachable from Unreal's
Python plugin, and this proves it: the attribute set, the modifiers, the
evaluation channels and the readings. It is written down because it was
measured, not assumed - each of these calls was run against UE 5.7.4 CL
51494982 on 2026-09-11 and answered.

The one thing it cannot do is `UAbilitySystemComponent::InitAbilityActorInfo`,
which is not a UFUNCTION. Every route into applying an effect dereferences
AbilityActorInfo, so without it the editor exits with

    Ensure condition failed: AbilityActorInfo.IsValid()
    AbilitySystemComponent.cpp:476

followed by an access violation. `Source/UEParity/ParityHelpers.h` exposes it,
and that is the whole reason a C++ module exists here at all.

Run with:

    UnrealEditor-Cmd.exe <harness>/UEParity.uproject -run=pythonscript         -script=<harness>/python_harness.py -unattended -nopause -nosplash -NullRHI
"""
import os

import unreal

TRAIL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "trail.txt")


def note(text):
    """Written and flushed line by line: a crash in the engine takes the
    interpreter with it, and a buffered log is a run that says nothing."""
    with open(TRAIL, "a") as handle:
        handle.write(text + chr(10))
        handle.flush()
        os.fsync(handle.fileno())


def fresh_component():
    """A component with nothing on it, on a throwaway actor.

    `EditorActorSubsystem` rather than a pawn: `AAbilitySystemTestPawn` is the
    obvious candidate and it is `notplaceable`, and spawning one from a
    commandlet takes the process down.
    """
    actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
    carrier = actors.spawn_actor_from_class(unreal.Actor, unreal.Vector(0, 0, 0))
    asc = unreal.new_object(unreal.AbilitySystemComponent, carrier)
    unreal.ParityHelpers.init_actor_info(asc, carrier, carrier)
    asc.init_stats(unreal.AbilitySystemTestAttributeSet, None)
    return asc, carrier


def attribute_named(asc, name):
    for attribute in asc.get_all_attributes():
        if attribute.get_editor_property("attribute_name") == name:
            return attribute
    raise LookupError(name)


# The struct's own fields refuse `set_editor_property` - they are
# EditDefaultsOnly and a Python struct is not a CDO - so a modifier is built
# the way Unreal writes one down and read back with `import_text`.
MODIFIER = (
    "(Attribute=%s,ModifierOp=%s,"
    "ModifierMagnitude=(MagnitudeCalculationType=ScalableFloat,"
    'ScalableFloatMagnitude=(Value=%f,Curve=(CurveTable=None,RowName=""),'
    'RegistryType="None")),'
    "EvaluationChannelSettings=(Channel=Channel%d))"
)


def modifier(attribute_text, operation, magnitude, channel=0):
    made = unreal.GameplayModifierInfo()
    made.import_text(MODIFIER % (attribute_text, operation, magnitude, channel))
    return made
