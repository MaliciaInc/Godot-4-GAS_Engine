## The outcome of resolving one magnitude, as a closed status plus the value
## when there is one.
##
## Its own enum, not AttributeEvaluationResult's or AttributeCaptureResult's:
## a magnitude fails for reasons neither of those can - a SetByCaller tag
## nobody set, a custom calculation that could not run - and a caller
## switching over this cannot silently miss one added later.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayMagnitudeResult extends RefCounted

enum Status {
	OK,
	INVALID_DEFINITION,
	MISSING_CAPTURE,
	MISSING_SET_BY_CALLER,
	ATTRIBUTE_NOT_FOUND,
	CALCULATION_FAILED,
	NON_FINITE_VALUE,
}

var status: GameplayMagnitudeResult.Status = Status.OK
var value: float = 0.0


func is_ok() -> bool:
	return status == Status.OK


static func ok(resolved_value: float) -> GameplayMagnitudeResult:
	var result: GameplayMagnitudeResult = GameplayMagnitudeResult.new()
	result.value = resolved_value
	return result


static func failure(failure_status: GameplayMagnitudeResult.Status) -> GameplayMagnitudeResult:
	var result: GameplayMagnitudeResult = GameplayMagnitudeResult.new()
	result.status = failure_status
	return result
