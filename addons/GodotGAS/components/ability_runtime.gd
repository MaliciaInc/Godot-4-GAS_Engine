## Granted abilities, the activation gate and input routing.
##
## The registry holds `GameplayAbilitySpec`s, each identified by a
## `GameplayAbilityHandle` rather than the Node underneath it - a handle from
## another ASC can never resolve here by coincidence of a reused id.
##
## Granting is a two-step transaction: `prepare_ability_grant` instantiates
## and validates once, `commit_prepared_grant`/`discard_prepared_grant`
## register or free it. `give_ability` does both; nothing else validates.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityRuntime extends RefCounted

## Why an activation was refused. Closed, so a switch cannot silently miss one.
enum ActivationError {
	NONE,
	ALREADY_ACTIVE,
	ON_COOLDOWN,
	BLOCKED_TAG,
	MISSING_TAG,
	INSUFFICIENT_RESOURCES,
	INTERNAL_ERROR,
	## Marked for REMOVE_ON_ACTIVE_END removal - see mark_pending_removal().
	PENDING_REMOVAL,
	## Refused by another spec's block_abilities_query, or a block effect.
	BLOCKED_BY_ACTIVE_ABILITY,
}

var owner_asc: AbilitySystemComponent = null
var tags: GameplayTagRuntime = null
var tasks: AbilityTaskRuntime = AbilityTaskRuntime.new()

## How a spec's instancing policy turns into a running Node.
var instancing: AbilityInstancingRuntime = AbilityInstancingRuntime.new()

## Effective tags, cancel/block matching, activation-owned tag refcounting.
var tag_semantics: AbilityTagSemanticsRuntime = AbilityTagSemanticsRuntime.new()

## ON_GRANTED's one attempt, PASSIVE's continuous reevaluation.
var policies: AbilityActivationPolicyRuntime = AbilityActivationPolicyRuntime.new()

var _specs: Array[GameplayAbilitySpec] = []
var _specs_by_id: Dictionary[int, GameplayAbilitySpec] = {}
var _next_handle_id: int = 1
var _held_inputs: Array[int] = []


#region Grant pipeline
## Instantiate `scene` once and validate it. Registers nothing until committed.
func prepare_ability_grant(
	scene: PackedScene, level: float, input_id: int, source: GameplayAbilitySource
) -> PreparedAbilityGrant:
	var prepared: PreparedAbilityGrant = PreparedAbilityGrant.new()
	prepared.level = level
	prepared.input_id = input_id
	prepared.source = source

	if scene == null:
		prepared.validation.status = AbilityGrantValidationResult.Status.SCENE_MISSING
		return prepared

	var instance: Node = scene.instantiate()
	if instance == null:
		prepared.validation.status = AbilityGrantValidationResult.Status.INSTANTIATION_FAILED
		return prepared

	var probe: GameplayAbility = instance as GameplayAbility
	if probe == null:
		# Never added to a tree, so an immediate free is safe.
		instance.free()
		prepared.validation.status = AbilityGrantValidationResult.Status.ROOT_NOT_GAMEPLAY_ABILITY
		return prepared

	var definition: GameplayAbilityDefinitionSnapshot = GameplayAbilityDefinitionSnapshot.from_probe(scene, probe)
	# A passive is a continuous state; several auto PER_EXECUTION instances
	# of it have no stable semantics, refused rather than forced to PER_ACTOR.
	if (
		definition.activation_policy == GameplayAbility.ActivationPolicy.PASSIVE
		and definition.instancing_policy == GameplayAbility.InstancingPolicy.PER_EXECUTION
	):
		probe.free()
		prepared.validation.status = AbilityGrantValidationResult.Status.INVALID_DEFINITION
		return prepared

	prepared.probe = probe
	prepared.definition = definition
	return prepared


## Register a validated preparation as a real grant. Refuses a null,
## already-consumed, or invalid one - without freeing anything.
func commit_prepared_grant(prepared: PreparedAbilityGrant) -> GameplayAbilityHandle:
	if prepared == null or prepared.consumed or not prepared.validation.is_ok():
		return GameplayAbilityHandle.new()

	var handle: GameplayAbilityHandle = GameplayAbilityHandle.new()
	handle.owner_instance_id = owner_asc.get_instance_id() if owner_asc != null else 0
	handle.id = _next_handle_id
	_next_handle_id += 1

	var spec: GameplayAbilitySpec = GameplayAbilitySpec.new()
	spec.handle = handle
	spec.definition = prepared.definition
	spec.level = prepared.level
	spec.input_id = prepared.input_id
	spec.source = prepared.source

	var probe: GameplayAbility = prepared.probe
	if prepared.definition.instancing_policy == GameplayAbility.InstancingPolicy.PER_ACTOR:
		probe.current_spec = spec
		probe.owner_asc = owner_asc
		spec.per_actor_instance = probe
		if owner_asc != null:
			owner_asc.add_child(probe)
	else:
		# PER_EXECUTION keeps no persistent instance: never treed.
		probe.free()

	_specs.append(spec)
	_specs_by_id[handle.id] = spec
	prepared.consumed = true
	# Only now: the spec must resolve by handle before ON_GRANTED/PASSIVE try.
	policies.on_spec_granted(spec)
	return handle


## Free what a preparation instantiated, if never committed. Idempotent.
func discard_prepared_grant(prepared: PreparedAbilityGrant) -> void:
	if prepared == null or prepared.consumed:
		return
	prepared.consumed = true
	if prepared.probe != null:
		prepared.probe.free()


## Prepare, then commit if that succeeded, else an invalid handle. No other
## route grants an ability.
func give_ability(
	scene: PackedScene,
	level: float = 1.0,
	input_id: int = -1,
	source: GameplayAbilitySource = null
) -> GameplayAbilityHandle:
	var prepared: PreparedAbilityGrant = prepare_ability_grant(scene, level, input_id, source)
	if not prepared.validation.is_ok():
		discard_prepared_grant(prepared)
		return GameplayAbilityHandle.new()
	return commit_prepared_grant(prepared)
#endregion


#region Registry
## The spec a handle names, or null - never resolving by id coincidence.
func get_spec(handle: GameplayAbilityHandle) -> GameplayAbilitySpec:
	if handle == null or not handle.is_valid():
		return null
	if owner_asc == null or handle.owner_instance_id != owner_asc.get_instance_id():
		return null
	return _specs_by_id.get(handle.id)


## Every granted spec, as a copy, for the same reason the effects are.
func specs() -> Array[GameplayAbilitySpec]:
	return _specs.duplicate()


## Abort, cancel tasks, free the Node, drop the spec. False if unresolved.
func remove_ability(handle: GameplayAbilityHandle) -> bool:
	var spec: GameplayAbilitySpec = get_spec(handle)
	if spec == null:
		return false
	_retire(spec)
	return true


## Convenience for a caller holding the instance rather than its handle -
## resolves it through the instance's own spec and delegates.
func remove(ability: GameplayAbility) -> void:
	if ability == null:
		return
	remove_ability(ability.get_ability_handle())


## REMOVE_ON_ACTIVE_END - see AbilityInstancingRuntime.mark_pending_removal().
func mark_pending_removal(handle: GameplayAbilityHandle) -> void:
	instancing.mark_pending_removal(get_spec(handle))


func _retire(spec: GameplayAbilitySpec) -> void:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and is_instance_valid(instance):
		# Must not outlive its activation - else ability_ended never fires.
		if instance.is_active:
			instance.abort_ability(GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		tasks.cancel_for_ability(instance, GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		instance.owner_asc = null
		instance.current_spec = null
		instance.queue_free()
	# Snapshot: aborting a PER_EXECUTION instance erases it from this array.
	for execution: GameplayAbility in spec.active_instances.duplicate():
		if is_instance_valid(execution) and execution.is_active:
			execution.abort_ability(GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		tasks.cancel_for_ability(execution, GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
	spec.active_instances.clear()
	_specs.erase(spec)
	_specs_by_id.erase(spec.handle.id)
	policies.request_reevaluation()


## Abort every running ability, for cleanup - PER_ACTOR stays idle after,
## PER_EXECUTION has no idle state so aborting frees it too, same as an end.
func abort_all(
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED
) -> void:
	# A passive aborted below must not restart mid-loop - see .suspended.
	policies.suspended = true
	for spec: GameplayAbilitySpec in _specs.duplicate():
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance) and instance.is_active:
			instance.abort_ability(reason)
		for execution: GameplayAbility in spec.active_instances.duplicate():
			if is_instance_valid(execution) and execution.is_active:
				execution.abort_ability(reason)
	tasks.cancel_all(reason)
	policies.suspended = false
	# ASC_CLEANUP: everything is about to be cleared, never reevaluated.
	if reason != GameplayAbilityTask.CancelReason.ASC_CLEANUP:
		policies.request_reevaluation()


func clear() -> void:
	_specs.clear()
	_specs_by_id.clear()
	_held_inputs.clear()
#endregion


#region Activation gate
## Whether a spec may activate, and why not - a reason, not a bare bool.
func activation_error(spec: GameplayAbilitySpec) -> ActivationError:
	if spec == null or spec.definition == null:
		return ActivationError.INTERNAL_ERROR
	if spec.pending_remove:
		return ActivationError.PENDING_REMOVAL
	# PER_EXECUTION keeps per_actor_instance null by construction, never refused here.
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and instance.is_active:
		return ActivationError.ALREADY_ACTIVE
	if query_matches_runtime(spec.definition.activation_blocked_query, tags):
		return ActivationError.BLOCKED_TAG
	if tags.has_any(get_cooldown_tags(spec)):
		return ActivationError.ON_COOLDOWN
	var required: GameplayTagQuery = spec.definition.activation_required_query
	if required != null and not required.is_empty() and not required.matches_runtime(tags):
		return ActivationError.MISSING_TAG
	if tag_semantics.blocked_by_active_ability(spec):
		return ActivationError.BLOCKED_BY_ACTIVE_ABILITY
	if owner_asc != null and not spec.definition.costs.is_empty():
		# The same resolver commit_ability() uses - never disagrees.
		var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
			spec.definition.costs, owner_asc, spec.level
		)
		if resolved.status == GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES:
			return ActivationError.INSUFFICIENT_RESOURCES
		if resolved.status != GameplayResolvedCost.Status.OK:
			return ActivationError.INTERNAL_ERROR
	return ActivationError.NONE


## Public: AbilityActivationPolicyRuntime needs the same check.
static func query_matches_runtime(query: GameplayTagQuery, runtime: GameplayTagRuntime) -> bool:
	return query != null and not query.is_empty() and query.matches_runtime(runtime)


func can_activate(spec: GameplayAbilitySpec) -> bool:
	return activation_error(spec) == ActivationError.NONE


## See AbilityActivationPolicyRuntime.request_reevaluation().
func request_passive_reevaluation() -> void:
	policies.request_reevaluation()


## See AbilityActivationPolicyRuntime.reevaluate().
func reevaluate_passives() -> void:
	policies.reevaluate()


## See AbilityActivationPolicyRuntime.active_requirements_error().
func active_requirements_error(spec: GameplayAbilitySpec) -> ActivationError:
	return policies.active_requirements_error(spec)


## See AbilityTagSemanticsRuntime.effective_ability_tags().
static func effective_ability_tags(spec: GameplayAbilitySpec) -> Array[StringName]:
	return AbilityTagSemanticsRuntime.effective_ability_tags(spec)


## See AbilityTagSemanticsRuntime.cancel_matching_query().
func cancel_matching_query(query: GameplayTagQuery, excluding: GameplayAbilitySpec = null) -> void:
	tag_semantics.cancel_matching_query(query, excluding)


## See AbilityTagSemanticsRuntime.cancel_with_tags().
func cancel_with_tags(cancel_tags: Array[StringName]) -> void:
	tag_semantics.cancel_with_tags(cancel_tags)
#endregion


#region Cooldowns
## Own tag, shared cooldowns', and any declared explicitly - one place.
static func get_cooldown_tags(spec: GameplayAbilitySpec) -> Array[StringName]:
	var cooldown_tags: Array[StringName] = []
	if spec == null or spec.definition == null:
		return cooldown_tags
	if spec.definition.cooldown_effect != null:
		cooldown_tags.append_array(spec.definition.cooldown_effect.get_granted_tags())
	for effect: GameplayEffect in spec.definition.shared_cooldown_effects:
		if effect != null:
			cooldown_tags.append_array(effect.get_granted_tags())
	cooldown_tags.append_array(spec.definition.shared_cooldown_tags)
	return cooldown_tags


## Everything a UI needs, read fresh from the tags cooldown effects grant -
## never an own clock, which would part company the first early refresh.
func get_ability_cooldown_state(handle: GameplayAbilityHandle) -> AbilityCooldownState:
	var state: AbilityCooldownState = AbilityCooldownState.new()
	var spec: GameplayAbilitySpec = get_spec(handle)
	if spec == null or owner_asc == null:
		return state

	for tag: StringName in get_cooldown_tags(spec):
		# A tag shared between two of its cooldowns is one wait, not two.
		if state.tags.has(tag):
			continue
		state.tags.append(tag)

		var seconds: float = owner_asc.get_tag_duration_remaining(tag)
		if is_inf(seconds):
			state.infinite = true
		elif seconds > state.seconds_remaining:
			state.seconds_remaining = seconds

		var turns: int = owner_asc.get_tag_turns_remaining(tag)
		if turns > state.turns_remaining:
			state.turns_remaining = turns

		if owner_asc.has_tag(tag):
			state.active = true

	if state.infinite or state.seconds_remaining > 0.0 or state.turns_remaining > 0:
		state.active = true
	return state
#endregion


#region Input routing
## `unbind_others` releases any other spec holding the slot already.
func bind_to_input(ability: GameplayAbility, input_id: int, unbind_others: bool = true) -> bool:
	if ability == null or ability.current_spec == null or not _specs.has(ability.current_spec):
		push_error("GodotGAS: cannot bind an ability that was never granted to this ASC.")
		return false

	if unbind_others:
		for spec: GameplayAbilitySpec in _specs:
			if spec != ability.current_spec and spec.input_id == input_id:
				spec.input_id = -1

	ability.current_spec.input_id = input_id
	return true


## As a copy: a caller clearing this must not leave the runtime believing nothing is pressed.
func held_inputs() -> Array[int]:
	return _held_inputs.duplicate()


func input_pressed(input_id: int) -> void:
	if not _held_inputs.has(input_id):
		_held_inputs.append(input_id)
	# Formal tasks hear the transition before an active ability's ad hoc hooks
	# - if a task ends the ability, the hook below no longer runs.
	tasks.input_pressed(input_id)
	# Snapshot: a sibling granted by this press must not also receive it.
	for spec: GameplayAbilitySpec in _specs.duplicate():
		if spec.input_id != input_id:
			continue
		_deliver_input(
			spec,
			func(a: GameplayAbility) -> void: a._input_pressed(owner_asc),
			func(a: GameplayAbility) -> void: a._active_input_pressed(owner_asc)
		)
		# PER_EXECUTION has no instance to ask above, so a press still means
		# "start one more" even while an earlier one keeps running.
		if (
			spec.definition != null
			and spec.definition.instancing_policy == GameplayAbility.InstancingPolicy.PER_EXECUTION
		):
			instancing.activate_spec(spec)


func input_released(input_id: int) -> void:
	_held_inputs.erase(input_id)
	tasks.input_released(input_id)
	for spec: GameplayAbilitySpec in _specs.duplicate():
		if spec.input_id == input_id:
			_deliver_input(
				spec,
				func(a: GameplayAbility) -> void: a._input_released(owner_asc),
				func(a: GameplayAbility) -> void: a._active_input_released(owner_asc)
			)


## PER_ACTOR's one instance, or a snapshot of every PER_EXECUTION instance
## already running - never a fresh one, a transition does not start anything.
func _deliver_input(
	spec: GameplayAbilitySpec, per_actor: Callable, per_execution: Callable
) -> void:
	if spec.definition == null:
		return
	if spec.definition.instancing_policy == GameplayAbility.InstancingPolicy.PER_ACTOR:
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance):
			per_actor.call(instance)
		return
	for execution: GameplayAbility in spec.active_instances.duplicate():
		if is_instance_valid(execution) and execution.is_active:
			per_execution.call(execution)
#endregion


#region Ability tasks
## Small pass-throughs - the task runtime owns the tasks, this only forwards.
func register_task(task: GameplayAbilityTask) -> GameplayAbilityTask:
	return tasks.register(task)


func cancel_tasks_for_ability(ability: GameplayAbility, reason: GameplayAbilityTask.CancelReason) -> void:
	tasks.cancel_for_ability(ability, reason)


func submit_target_data(ability: GameplayAbility, data: GameplayAbilityTargetData) -> void:
	tasks.target_data(ability, data)


func advance_time(delta: float) -> void:
	tasks.advance_time(delta)
#endregion
