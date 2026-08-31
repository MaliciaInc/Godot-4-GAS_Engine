## Granted abilities, the activation gate and input routing.
##
## What was granted and what is running are different things: the registry
## holds `GameplayAbilitySpec`s, each identified by a `GameplayAbilityHandle`
## rather than by the Node instance underneath it - a handle from another ASC
## can never resolve here by coincidence of a locally-reused id.
##
## Granting is a two-step transaction: `prepare_ability_grant` instantiates
## the scene and validates it exactly once, and either
## `commit_prepared_grant` registers what it found or `discard_prepared_grant`
## frees it. `give_ability` does both in sequence; nothing else validates a
## grant a second way.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name AbilityRuntime extends RefCounted

## Why an activation was refused. Closed: a caller switching over this cannot
## silently miss a reason added later.
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
	## Refused by another spec's block_abilities_query or an uninhibited
	## GameplayEffectBlockAbilityTagsComponent - never BLOCKED_TAG.
	BLOCKED_BY_ACTIVE_ABILITY,
}

var owner_asc: AbilitySystemComponent = null
var tags: GameplayTagRuntime = null

## Every task any granted ability is currently waiting on.
var tasks: AbilityTaskRuntime = AbilityTaskRuntime.new()

## How a spec's instancing policy turns into a running Node.
var instancing: AbilityInstancingRuntime = AbilityInstancingRuntime.new()

## Effective tags, cancel/block matching, activation-owned tag refcounting.
var tag_semantics: AbilityTagSemanticsRuntime = AbilityTagSemanticsRuntime.new()

var _specs: Array[GameplayAbilitySpec] = []
var _specs_by_id: Dictionary[int, GameplayAbilitySpec] = {}
var _next_handle_id: int = 1
var _held_inputs: Array[int] = []


#region Grant pipeline
## Instantiate `scene` once and validate it. Registers nothing: the result
## must be committed or discarded before this operation is considered done.
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
		# Never added to a tree, so an immediate free is safe - no one-frame
		# window where a queue_free() here left the orphan counter to catch.
		instance.free()
		prepared.validation.status = AbilityGrantValidationResult.Status.ROOT_NOT_GAMEPLAY_ABILITY
		return prepared

	prepared.probe = probe
	prepared.definition = GameplayAbilityDefinitionSnapshot.from_probe(scene, probe)
	return prepared


## Register a validated preparation as a real grant. Refuses - without
## freeing anything, since the caller still owns an unconsumed preparation -
## a null, already-consumed, or invalid one.
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
		# PER_EXECUTION keeps no persistent instance: the probe only validated
		# the scene and captured the snapshot above, and was never treed.
		probe.free()

	_specs.append(spec)
	_specs_by_id[handle.id] = spec
	prepared.consumed = true
	return handle


## Free what a preparation instantiated, if never committed. Idempotent - a
## second call on an already-consumed preparation is a no-op, never a double free.
func discard_prepared_grant(prepared: PreparedAbilityGrant) -> void:
	if prepared == null or prepared.consumed:
		return
	prepared.consumed = true
	if prepared.probe != null:
		prepared.probe.free()


## The official convenience: prepare, then commit if that succeeded, or an
## invalid handle if it did not. No other route grants an ability.
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
## The spec a handle names, or null: an unknown id, a handle from another
## ASC, or an invalid handle all answer null rather than resolving by
## coincidence.
func get_spec(handle: GameplayAbilityHandle) -> GameplayAbilitySpec:
	if handle == null or not handle.is_valid():
		return null
	if owner_asc == null or handle.owner_instance_id != owner_asc.get_instance_id():
		return null
	return _specs_by_id.get(handle.id)


## Every granted spec, as a copy, for the same reason the effects are.
func specs() -> Array[GameplayAbilitySpec]:
	return _specs.duplicate()


## Retire a grant by handle: abort its running instance, cancel its tasks,
## free the Node, drop the spec. False when the handle does not resolve here.
func remove_ability(handle: GameplayAbilityHandle) -> bool:
	var spec: GameplayAbilitySpec = get_spec(handle)
	if spec == null:
		return false
	_retire(spec)
	return true


## Convenience for a caller holding the running instance rather than its
## handle. A stateless wrapper over remove_ability - resolves the handle
## through the instance's own spec and delegates.
func remove(ability: GameplayAbility) -> void:
	if ability == null:
		return
	remove_ability(ability.get_ability_handle())


## REMOVE_ON_ACTIVE_END: retires `handle` once every in-flight activation
## ends, or immediately if none is - see
## AbilityInstancingRuntime.mark_pending_removal().
func mark_pending_removal(handle: GameplayAbilityHandle) -> void:
	instancing.mark_pending_removal(get_spec(handle))


func _retire(spec: GameplayAbilitySpec) -> void:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and is_instance_valid(instance):
		# A removed ability must not outlive its own activation - freeing the
		# node mid-cast would leave ability_ended unfired and its commit stuck.
		if instance.is_active:
			instance.abort_ability(GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		tasks.cancel_for_ability(instance, GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		instance.owner_asc = null
		instance.current_spec = null
		instance.queue_free()
	# Every PER_EXECUTION instance still running retires the same way, from a
	# snapshot: aborting one erases it from this array as it goes.
	for execution: GameplayAbility in spec.active_instances.duplicate():
		if is_instance_valid(execution) and execution.is_active:
			execution.abort_ability(GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		tasks.cancel_for_ability(execution, GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
	spec.active_instances.clear()
	_specs.erase(spec)
	_specs_by_id.erase(spec.handle.id)


## Abort every running ability. Used by cleanup, which must leave the ASC in a
## state a second cleanup can safely see - PER_ACTOR stays idle afterward,
## but PER_EXECUTION has no idle state, so aborting frees it too, the same
## `ability_ended` path an end uses.
func abort_all(
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED
) -> void:
	for spec: GameplayAbilitySpec in _specs.duplicate():
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance) and instance.is_active:
			instance.abort_ability(reason)
		for execution: GameplayAbility in spec.active_instances.duplicate():
			if is_instance_valid(execution) and execution.is_active:
				execution.abort_ability(reason)
	tasks.cancel_all(reason)


func clear() -> void:
	_specs.clear()
	_specs_by_id.clear()
	_held_inputs.clear()
#endregion


#region Activation gate
## Whether a granted spec may activate, and why not when it may not.
##
## Returns the reason rather than a bare bool so the caller emits one signal
## carrying the cause, not a branch per caller announcing its own.
func activation_error(spec: GameplayAbilitySpec) -> ActivationError:
	if spec == null or spec.definition == null:
		return ActivationError.INTERNAL_ERROR
	if spec.pending_remove:
		return ActivationError.PENDING_REMOVAL
	# PER_ACTOR's one instance blocks a second cast while running; PER_EXECUTION
	# keeps per_actor_instance null by construction, never refused here.
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and instance.is_active:
		return ActivationError.ALREADY_ACTIVE
	if _query_matches_runtime(spec.definition.activation_blocked_query, tags):
		return ActivationError.BLOCKED_TAG
	if tags.has_any(get_cooldown_tags(spec)):
		return ActivationError.ON_COOLDOWN
	var required: GameplayTagQuery = spec.definition.activation_required_query
	if required != null and not required.is_empty() and not required.matches_runtime(tags):
		return ActivationError.MISSING_TAG
	if tag_semantics.blocked_by_active_ability(spec):
		return ActivationError.BLOCKED_BY_ACTIVE_ABILITY
	if owner_asc != null and not spec.definition.costs.is_empty():
		# The same resolver commit_ability() uses - a preview here and the
		# actual charge can never disagree.
		var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
			spec.definition.costs, owner_asc, spec.level
		)
		if resolved.status == GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES:
			return ActivationError.INSUFFICIENT_RESOURCES
		if resolved.status != GameplayResolvedCost.Status.OK:
			return ActivationError.INTERNAL_ERROR
	return ActivationError.NONE


static func _query_matches_runtime(query: GameplayTagQuery, runtime: GameplayTagRuntime) -> bool:
	return query != null and not query.is_empty() and query.matches_runtime(runtime)


func can_activate(spec: GameplayAbilitySpec) -> bool:
	return activation_error(spec) == ActivationError.NONE


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
## Every tag that represents a cooldown for this grant: the definition's own,
## its shared cooldown effects', and any declared explicitly - the one place
## this is computed, so the gate and a cooldown reading never disagree.
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


## Everything a UI needs to draw one grant's cooldown, read fresh from the
## tags its definition's cooldown effects grant - never from an own clock,
## which would part company the first time it refreshed or expired early.
func get_ability_cooldown_state(handle: GameplayAbilityHandle) -> AbilityCooldownState:
	var state: AbilityCooldownState = AbilityCooldownState.new()
	var spec: GameplayAbilitySpec = get_spec(handle)
	if spec == null or owner_asc == null:
		return state

	for tag: StringName in get_cooldown_tags(spec):
		# A tag shared between the ability's own cooldown and a shared one is
		# one wait, not two, and must not be counted twice.
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
## Bind an ability to an input slot. `unbind_others` releases any other
## granted spec holding that slot, so two abilities never both answer one press.
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


## The slots currently held down, as a copy: a caller clearing this would
## leave the runtime believing nothing is pressed.
func held_inputs() -> Array[int]:
	return _held_inputs.duplicate()


func input_pressed(input_id: int) -> void:
	if not _held_inputs.has(input_id):
		_held_inputs.append(input_id)
	# Formal tasks hear the transition before an active ability's ad hoc hooks.
	# If a task ends the ability the hook below no longer runs, which is the
	# point: one press must not both finish a cast and be re-read by it.
	tasks.input_pressed(input_id)
	# Snapshot: an ability that grants another one on press must not have its
	# new sibling receive the same press.
	for spec: GameplayAbilitySpec in _specs.duplicate():
		if spec.input_id != input_id:
			continue
		_deliver_input(
			spec,
			func(a: GameplayAbility) -> void: a._input_pressed(owner_asc),
			func(a: GameplayAbility) -> void: a._active_input_pressed(owner_asc)
		)
		# PER_ACTOR's instance already decided above whether the press
		# started or continued it. PER_EXECUTION has none to ask, so the
		# spec may start one more of its own too - a press never stops
		# meaning "start" just because an earlier one is still running.
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


## Deliver an input transition to whatever should hear it now: PER_ACTOR's one
## instance, or a snapshot of every PER_EXECUTION instance already running -
## never a fresh one, since a transition does not itself start anything.
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
## Small pass-throughs. The task runtime owns the tasks; this only forwards,
## so one place decides what still running means.
func register_task(task: GameplayAbilityTask) -> GameplayAbilityTask:
	return tasks.register(task)


func cancel_tasks_for_ability(ability: GameplayAbility, reason: GameplayAbilityTask.CancelReason) -> void:
	tasks.cancel_for_ability(ability, reason)


func submit_target_data(ability: GameplayAbility, data: GameplayAbilityTargetData) -> void:
	tasks.target_data(ability, data)


func advance_time(delta: float) -> void:
	tasks.advance_time(delta)
#endregion
