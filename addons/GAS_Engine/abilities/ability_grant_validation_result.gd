## Why preparing an ability grant refused, when it did.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name AbilityGrantValidationResult extends RefCounted

enum Status {
	OK,
	SCENE_MISSING,
	INSTANTIATION_FAILED,
	ROOT_NOT_GAMEPLAY_ABILITY,
	INVALID_DEFINITION,
}

var status: AbilityGrantValidationResult.Status = Status.OK


func is_ok() -> bool:
	return status == Status.OK
