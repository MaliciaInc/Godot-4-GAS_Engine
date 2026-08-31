## A stable identity for one running persistent cue, independent of the
## `GameplayCueNotify` instance the manager happens to have parked it in -
## the pool can hand that Node to a different playback entirely once this
## one ends, the same way GameplayAbilityHandle/GameplayEffectHandle outlive
## the object they once named.
##
## This file is in the GameplayCueManager autoload's parse-time closure -
## see gameplay_cue_params.gd for why every type it names comes from
## `preload`, never a bare global `class_name` reference, inside that
## closure.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayCueHandle extends RefCounted

const INVALID_ID: int = 0

var id: int = INVALID_ID


func is_valid() -> bool:
	return id != INVALID_ID
