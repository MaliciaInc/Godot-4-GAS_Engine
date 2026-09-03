## Whether one component allows this application to proceed, and why not when
## it does not.
##
## Shared by GameplayEffectComponent.can_apply() and
## GameplayEffectApplicationRequirement.can_apply(): a custom requirement is a
## component's decision by delegation, not a second vocabulary for the same
## question.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectComponentDecision extends RefCounted

var allowed: bool = true
var reason: String = ""


func is_allowed() -> bool:
	return allowed


static func allow() -> GameplayEffectComponentDecision:
	return GameplayEffectComponentDecision.new()


static func deny(reason: String = "") -> GameplayEffectComponentDecision:
	var decision: GameplayEffectComponentDecision = GameplayEffectComponentDecision.new()
	decision.allowed = false
	decision.reason = reason
	return decision
