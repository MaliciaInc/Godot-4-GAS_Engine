## Whether one GameplayEffectComponent's authored definition is legal.
##
## Returned by validate_definition() before an effect is ever applied - a
## design-time check, not a per-application decision.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectComponentValidationResult extends RefCounted

enum Status {
	OK,
	INVALID_COMPONENT,
}

var status: GameplayEffectComponentValidationResult.Status = Status.OK
var component: GameplayEffectComponent = null
var reason: String = ""


func is_ok() -> bool:
	return status == Status.OK


static func ok() -> GameplayEffectComponentValidationResult:
	return GameplayEffectComponentValidationResult.new()


static func invalid(
	component: GameplayEffectComponent, reason: String
) -> GameplayEffectComponentValidationResult:
	var result: GameplayEffectComponentValidationResult = GameplayEffectComponentValidationResult.new()
	result.status = Status.INVALID_COMPONENT
	result.component = component
	result.reason = reason
	return result
