## The project's gameplay cues: which scene answers which tag.
##
## Written by GAS_Engine and read back by it, and safe to edit by hand:
## this file is the registry rather than a copy of one, so there is
## nothing for it to fall out of step with.
##
## A cue asked for by a tag nobody bound falls back up the family:
## A.B.C, then A.B, then A, and the first binding found is the one
## that plays. A tag listed under OVERRIDE_PARENT ends that walk
## where it stands - with its own binding when it has one, and with
## silence when it has none.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0

@tool
class_name GameplayCues

const BINDINGS: Dictionary[StringName, PackedScene] = {
}


const OVERRIDE_PARENT: Array[StringName] = [
]
