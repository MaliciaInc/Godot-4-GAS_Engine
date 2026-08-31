## What preparing one component for an application produced: success (with an
## optional state to carry forward) or a rejection.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectComponentPreparationResult extends RefCounted

enum Status {
	OK,
	REJECTED,
}

var status: Status = Status.OK
var state: GameplayEffectComponentState = null
var reason: String = ""


func is_ok() -> bool:
	return status == Status.OK


static func ok(state: GameplayEffectComponentState = null) -> GameplayEffectComponentPreparationResult:
	var result: GameplayEffectComponentPreparationResult = GameplayEffectComponentPreparationResult.new()
	result.state = state
	return result


static func rejected(reason: String = "") -> GameplayEffectComponentPreparationResult:
	var result: GameplayEffectComponentPreparationResult = GameplayEffectComponentPreparationResult.new()
	result.status = Status.REJECTED
	result.reason = reason
	return result
