## What changing a running effect did, or why it did nothing.
##
## Mutating an active effect used to mean reaching into it and writing a field,
## which works right up to the moment the write is refused - and then nothing
## says so. A level set to NaN, a stack count set below one, a handle whose
## effect ended a frame ago: each of those is a different mistake, and a caller
## that got `false` for all three cannot tell which.
##
## So every mutation answers, and answers with which of them it was.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectMutationResult extends RefCounted

enum Status {
	SUCCESS,
	HANDLE_NOT_FOUND,
	INVALID_VALUE,
	INVALID_OPERATION,
	EVALUATION_FAILED,
}

var status: GameplayEffectMutationResult.Status = Status.SUCCESS

## The effect that was changed, when one was. Kept so a caller that mutated by
## handle does not have to resolve the handle a second time to see the result.
var active_effect: ActiveGameplayEffect = null


func is_ok() -> bool:
	return status == Status.SUCCESS


static func ok(active: ActiveGameplayEffect) -> GameplayEffectMutationResult:
	var made: GameplayEffectMutationResult = GameplayEffectMutationResult.new()
	made.active_effect = active
	return made


static func refused(why: GameplayEffectMutationResult.Status) -> GameplayEffectMutationResult:
	var made: GameplayEffectMutationResult = GameplayEffectMutationResult.new()
	made.status = why
	return made
