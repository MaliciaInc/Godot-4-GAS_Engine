## A blessing on yourself that wears off.
##
## No targeting and no waiting: the interesting part is the effect, which has a
## duration and can therefore be removed, expire, or be reapplied while it is
## still running. The ability itself ends immediately - a buff is not something
## you stand still for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends GameplayAbility

## HAS_DURATION. It runs on after this ability has already finished.
@export var blessing: GameplayEffect


func _activate_ability() -> bool:
	if not commit_ability().is_ok():
		return false

	owner_asc.apply_gameplay_effect(blessing, owner_asc, get_ability_level())
	end_ability()
	return true
