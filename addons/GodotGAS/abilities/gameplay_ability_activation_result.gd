## What `AbilityRuntime.try_activate()` answers: whether activation started,
## not whether it will finish. `SUCCESS` means the gates passed and
## `_begin_runtime_activation()` ran - never that `_activate_ability()` will
## return true. A body that later fails or cancels is reported through
## `AbilitySystemComponent.ability_runtime_ended`, not by revisiting this
## result. `ACTIVATION_FAILED` is reserved for a failure before execution
## ever started - the runtime instance could not be created.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAbilityActivationResult extends RefCounted

enum Status {
	SUCCESS,
	SPEC_NOT_FOUND,
	ALREADY_ACTIVE,
	ON_COOLDOWN,
	BLOCKED_BY_TAGS,
	MISSING_REQUIRED_TAGS,
	BLOCKED_BY_ACTIVE_ABILITY,
	INSUFFICIENT_RESOURCES,
	INVALID_DEFINITION,
	PENDING_REMOVAL,
	ACTIVATION_FAILED,
}

var status: Status = Status.SPEC_NOT_FOUND
var handle: GameplayAbilityHandle = null
var instance: GameplayAbility = null


func is_ok() -> bool:
	return status == Status.SUCCESS
