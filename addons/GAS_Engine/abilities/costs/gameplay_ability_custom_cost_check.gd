## Whether a custom cost can be paid right now, and why not.
##
## A bool would have been enough for the engine and useless to everything else:
## a button that greys itself out wants to say "no ammunition" rather than "no",
## and a refusal with no reason is one a UI has to guess at.
##
## The reason is a tag rather than a string because it is read by code first and
## by a person second - a game maps it to whatever its own language calls the
## thing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityCustomCostCheck extends RefCounted

var can_pay: bool = true

## Empty when it can be paid. Never empty when it cannot: a refusal that did not
## say why is one nobody can act on.
var reason: StringName = &""


static func allowed() -> GameplayAbilityCustomCostCheck:
	return GameplayAbilityCustomCostCheck.new()


static func refused(reason_tag: StringName) -> GameplayAbilityCustomCostCheck:
	var result: GameplayAbilityCustomCostCheck = GameplayAbilityCustomCostCheck.new()
	result.can_pay = false
	result.reason = reason_tag
	return result
