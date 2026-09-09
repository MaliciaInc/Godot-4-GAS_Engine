## One ability in a loadout, with the two things a grant needs beyond the scene.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilitySetEntry extends Resource

@export var ability_scene: PackedScene = null

## The level this entry is granted at, before the set's own multiplier.
@export var level: float = 1.0

## The input slot it answers, or -1 for one nothing presses.
@export var input_id: int = -1
