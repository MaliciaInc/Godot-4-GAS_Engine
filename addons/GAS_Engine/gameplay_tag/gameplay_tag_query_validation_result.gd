## Whether a GameplayTagQuery is a legal definition, and why not when it is not.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTagQueryValidationResult extends RefCounted

enum Status {
	OK,
	CYCLIC_EXPRESSION,
	EMPTY_TAG,
	INVALID_TAG,
}

var status: GameplayTagQueryValidationResult.Status = Status.OK

## The offending tag, for INVALID_TAG. Empty otherwise.
var invalid_tag: StringName = &""


func is_ok() -> bool:
	return status == Status.OK
