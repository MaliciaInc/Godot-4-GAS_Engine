## The outcome of resolving one attribute capture, as a closed status plus
## the value when there is one.
##
## Deliberately not AttributeEvaluationResult's Status: a capture fails for
## reasons a modifier evaluation never can - no source, no target - and a
## caller switching over this cannot silently miss one added later.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AttributeCaptureResult extends RefCounted

enum Status {
	OK,
	INVALID_DEFINITION,
	SOURCE_MISSING,
	TARGET_MISSING,
	ATTRIBUTE_NOT_FOUND,
	NON_FINITE_VALUE,
}

var status: AttributeCaptureResult.Status = Status.OK
var value: float = 0.0


func is_ok() -> bool:
	return status == Status.OK
