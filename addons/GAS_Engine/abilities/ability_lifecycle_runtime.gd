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

## How many activations this runtime has started, ever.
##
## The number an activation is stamped with. Monotonic and never reset, because
## its whole job is to be different from the one before it: an id that came
## round again would let a task believe it still owns something a later
## activation took.
var _activations: int = 0


#region Canonical activation
## Resolve, gate, instantiate and start - returns the moment activation
## begins, never waiting for `_activate_ability()` to finish. A channelled
## ability can run indefinitely; this call cannot.
## Activate by handle, carrying whatever it is being activated for.
##
## The compatibility door: an effect context alone is what a direct call means,
## and every caller that had one keeps working unchanged.
func try_activate(
	handle: GameplayAbilityHandle, context: GameplayEffectContext = null
) -> GameplayAbilityActivationResult:
	return try_activate_with(
		handle, GameplayAbilityActivationContext.from_effect_context(context)
	)


## Activate because this event happened.
##
## Separate from the effect-context door because the event is the thing that
## would otherwise be lost: which tag fired it, what magnitude it carried, who
## it was aimed at. An ability that had to rebuild any of that from the world
## would be guessing, because the world has moved on since.
func try_activate_from_event(
	handle: GameplayAbilityHandle, event: GameplayEventData
) -> GameplayAbilityActivationResult:
	return try_activate_with(
		handle, GameplayAbilityActivationContext.from_gameplay_event(event)
	)


## The one activation path. Everything else is a door into it.
func try_activate_with(
	handle: GameplayAbilityHandle, activation: GameplayAbilityActivationContext
) -> GameplayAbilityActivationResult:
	var context: GameplayEffectContext = (
		activation.effect_context if activation != null else null
	)
	var result: GameplayAbilityActivationResult = GameplayAbilityActivationResult.new()
	result.handle = handle
	var spec: GameplayAbilitySpec = ability_runtime.get_spec(handle)
	if spec == null:
		result.status = GameplayAbilityActivationResult.Status.SPEC_NOT_FOUND
		return result

	var error: AbilityRuntime.ActivationError = ability_runtime.activation_error(spec)
	if error == AbilityRuntime.ActivationError.NONE and activation != null:
		# Only an activation carrying an event can answer the source gates, and
		# only after the ordinary gates have had their say - a spec that is on
		# cooldown is on cooldown whoever asked.
		error = ability_runtime.source_gate_error(spec, activation.gameplay_event)
	if error != AbilityRuntime.ActivationError.NONE:
		result.status = _translate(error)
		spec.last_activation_result = result
		if ability_runtime.owner_asc != null:
			ability_runtime.owner_asc.ability_activation_failed.emit(spec.per_actor_instance, error)
		return result

	# Retriggering replaces rather than stacks: the activation in flight is
	# ended first, so the ability is announced as starting once for each time
	# somebody actually started it. Ended rather than cancelled, because the
	# player asked for this - it is not an interruption.
	var running: GameplayAbility = spec.per_actor_instance
	if (
		running != null
		and running.is_active
		and spec.definition.retrigger_while_active
	):
		running.end_ability(false)

	var instance: GameplayAbility = ability_runtime.instancing.instance_for_activation(spec)
	if instance == null:
		result.status = GameplayAbilityActivationResult.Status.ACTIVATION_FAILED
		spec.last_activation_result = result
		return result

	result.instance = instance
	instance._prepare_runtime_activation(context)
	instance._activation_context = activation
	_activations += 1
	instance.activation_id = _activations

	result.status = GameplayAbilityActivationResult.Status.SUCCESS
	spec.last_activation_result = result

	if ability_runtime.owner_asc != null:
		ability_runtime.owner_asc.ability_activated.emit(handle, instance)

	# The activation callback may have cancelled or removed the instance.
	if is_instance_valid(instance) and instance.is_active:
		instance._execute_runtime_activation()

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
