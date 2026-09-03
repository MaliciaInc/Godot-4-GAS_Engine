## Delegates the can-apply question to an arbitrary
## GameplayEffectApplicationRequirement Resource, for a check none of the
## other components express.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectCustomCanApplyComponent extends GameplayEffectComponent

@export var requirement: GameplayEffectApplicationRequirement = null


func can_apply(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	if requirement == null:
		return GameplayEffectComponentDecision.allow()
	return requirement.can_apply(request)
