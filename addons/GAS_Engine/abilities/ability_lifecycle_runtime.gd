## The canonical activation entry point, by handle, and give_and_activate_once
## on top of it.
##
## Split out of AbilityRuntime the same way AbilityInstancingRuntime/
## AbilityTagSemanticsRuntime are - `AbilityRuntime.try_activate()`/
## `give_and_activate_once()` are thin wrappers there, the logic lives here.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityLifecycleRuntime extends RefCounted

var ability_runtime: AbilityRuntime = null


#region Canonical activation
## Resolve, gate, instantiate and start - returns the moment activation
## begins, never waiting for `_activate_ability()` to finish. A channelled
## ability can run indefinitely; this call cannot.
func try_activate(
	handle: GameplayAbilityHandle, context: GameplayEffectContext = null
) -> GameplayAbilityActivationResult:
	var result: GameplayAbilityActivationResult = GameplayAbilityActivationResult.new()
	result.handle = handle
	var spec: GameplayAbilitySpec = ability_runtime.get_spec(handle)
	if spec == null:
		result.status = GameplayAbilityActivationResult.Status.SPEC_NOT_FOUND
		return result

	var error: AbilityRuntime.ActivationError = ability_runtime.activation_error(spec)
	if error != AbilityRuntime.ActivationError.NONE:
		result.status = _translate(error)
		spec.last_activation_result = result
		if ability_runtime.owner_asc != null:
			ability_runtime.owner_asc.ability_activation_failed.emit(spec.per_actor_instance, error)
		return result

	var instance: GameplayAbility = ability_runtime.instancing.instance_for_activation(spec)
	if instance == null:
		result.status = GameplayAbilityActivationResult.Status.ACTIVATION_FAILED
		spec.last_activation_result = result
		return result

	result.instance = instance
	instance._begin_runtime_activation(context)
	result.status = GameplayAbilityActivationResult.Status.SUCCESS
	spec.last_activation_result = result
	if ability_runtime.owner_asc != null:
		ability_runtime.owner_asc.ability_activated.emit(handle, instance)
	return result


static func _translate(error: AbilityRuntime.ActivationError) -> GameplayAbilityActivationResult.Status:
	match error:
		AbilityRuntime.ActivationError.ALREADY_ACTIVE:
			return GameplayAbilityActivationResult.Status.ALREADY_ACTIVE
		AbilityRuntime.ActivationError.ON_COOLDOWN:
			return GameplayAbilityActivationResult.Status.ON_COOLDOWN
		AbilityRuntime.ActivationError.BLOCKED_TAG:
			return GameplayAbilityActivationResult.Status.BLOCKED_BY_TAGS
		AbilityRuntime.ActivationError.MISSING_TAG:
			return GameplayAbilityActivationResult.Status.MISSING_REQUIRED_TAGS
		AbilityRuntime.ActivationError.BLOCKED_BY_ACTIVE_ABILITY:
			return GameplayAbilityActivationResult.Status.BLOCKED_BY_ACTIVE_ABILITY
		AbilityRuntime.ActivationError.INSUFFICIENT_RESOURCES:
			return GameplayAbilityActivationResult.Status.INSUFFICIENT_RESOURCES
		AbilityRuntime.ActivationError.PENDING_REMOVAL:
			return GameplayAbilityActivationResult.Status.PENDING_REMOVAL
		_:
			return GameplayAbilityActivationResult.Status.INVALID_DEFINITION
#endregion


#region Give and activate once
## Give, activate, and retire: never started -> retired immediately; started
## -> retired once active_count returns to 0. Never leaves a dead spec behind
## either way, and PENDING_REMOVAL (set the instant activation starts, before
## this even returns) refuses any second activation of the same handle -
## PER_EXECUTION included, so this spec can only ever run the one execution
## this call launched.
func give_and_activate_once(
	ability_scene: PackedScene,
	level: float = 1.0,
	source: GameplayAbilitySource = null,
	context: GameplayEffectContext = null
) -> GameplayAbilityActivationResult:
	var handle: GameplayAbilityHandle = ability_runtime.give_ability(ability_scene, level, -1, source)
	if not handle.is_valid():
		var refused: GameplayAbilityActivationResult = GameplayAbilityActivationResult.new()
		refused.status = GameplayAbilityActivationResult.Status.INVALID_DEFINITION
		return refused

	var result: GameplayAbilityActivationResult = try_activate(handle, context)
	if result.is_ok():
		ability_runtime.remove_ability(handle, AbilityRuntime.AbilityRemovalPolicy.AFTER_ACTIVE_END)
	else:
		ability_runtime.remove_ability(handle)
	return result
#endregion
