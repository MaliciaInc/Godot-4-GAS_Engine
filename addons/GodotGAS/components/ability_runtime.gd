## Granted abilities, the activation gate and input routing.
##
## What was granted and what is running are different things: the registry
## holds `GameplayAbilitySpec`s, each identified by a `GameplayAbilityHandle`
## rather than by the Node instance underneath it. A handle from another ASC
## can never resolve here by coincidence of a locally-reused id - every lookup
## checks the handle's owner first.
##
## Granting itself is a two-step transaction: `prepare_ability_grant`
## instantiates the scene and validates it exactly once, and either
## `commit_prepared_grant` registers what it found or `discard_prepared_grant`
## frees it. `give_ability` is the convenience that does both in sequence;
## nothing else in this addon validates a grant a second way.
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
}

var owner_asc: AbilitySystemComponent = null
var tags: GameplayTagRuntime = null

## Every task any granted ability is currently waiting on.
var tasks: AbilityTaskRuntime = AbilityTaskRuntime.new()

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
		# Never added to a tree, so nothing is mid-callback on it: freeing
		# immediately rather than deferring is safe, and avoids the one-frame
		# window where this instance is neither owned nor yet gone - the
		# window a `queue_free()` here left the orphan counter to catch.
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
	probe.current_spec = spec
	probe.owner_asc = owner_asc
	spec.per_actor_instance = probe

	if owner_asc != null:
		owner_asc.add_child(probe)

	_specs.append(spec)
	_specs_by_id[handle.id] = spec
	prepared.consumed = true
	return handle


## Free what a preparation instantiated, if it was never committed. Idempotent:
## a second call on an already-consumed preparation does nothing, never a
## double free.
func discard_prepared_grant(prepared: PreparedAbilityGrant) -> void:
	if prepared == null or prepared.consumed:
		return
	prepared.consumed = true
	if prepared.probe != null:
		# Same reasoning as prepare_ability_grant's own discard: never added
		# to a tree, so an immediate free is safe and leaves no orphan window.
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


func _retire(spec: GameplayAbilitySpec) -> void:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and is_instance_valid(instance):
		# A removed ability must not outlive its own activation: freeing the
		# node mid-cast would leave `ability_ended` unfired and its commit
		# forgotten by nothing that would ever undo it.
		if instance.is_active:
			instance.abort_ability(GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		tasks.cancel_for_ability(instance, GameplayAbilityTask.CancelReason.ABILITY_REMOVED)
		instance.owner_asc = null
		instance.current_spec = null
		instance.queue_free()
	_specs.erase(spec)
	_specs_by_id.erase(spec.handle.id)


## Abort every running ability without freeing anything. Used by cleanup,
## which must leave the ASC in a state a second cleanup can safely see.
func abort_all(
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED
) -> void:
	for spec: GameplayAbilitySpec in _specs.duplicate():
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance) and instance.is_active:
			instance.abort_ability(reason)
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
## carrying the cause. Upstream emitted from inside each branch, which meant
## the gate could not be asked a question without also announcing the answer.
func activation_error(spec: GameplayAbilitySpec) -> ActivationError:
	if spec == null or spec.definition == null:
		return ActivationError.INTERNAL_ERROR
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and instance.is_active:
		return ActivationError.ALREADY_ACTIVE
	if tags.has_any(spec.definition.legacy_activation_blocked_tags):
		return ActivationError.BLOCKED_TAG
	if tags.has_any(get_cooldown_tags(spec)):
		return ActivationError.ON_COOLDOWN
	if not tags.has_all(spec.definition.legacy_activation_required_tags):
		return ActivationError.MISSING_TAG
	if owner_asc != null and not spec.definition.costs.is_empty():
		# The same resolver commit_ability() uses, so a preview here and the
		# charge commit_ability() actually takes can never disagree.
		var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
			spec.definition.costs, owner_asc, spec.level
		)
		if resolved.status == GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES:
			return ActivationError.INSUFFICIENT_RESOURCES
		if resolved.status != GameplayResolvedCost.Status.OK:
			return ActivationError.INTERNAL_ERROR
	return ActivationError.NONE


func can_activate(spec: GameplayAbilitySpec) -> bool:
	return activation_error(spec) == ActivationError.NONE


## Abort any running ability whose spec carries one of these tags, or that
## these tags would block.
func cancel_with_tags(cancel_tags: Array[StringName]) -> void:
	for spec: GameplayAbilitySpec in _specs:
		var instance: GameplayAbility = spec.per_actor_instance
		if instance == null or not is_instance_valid(instance) or not instance.is_active:
			continue
		for tag: StringName in cancel_tags:
			if (
				spec.definition.legacy_ability_tag == tag
				or spec.definition.legacy_activation_blocked_tags.has(tag)
			):
				instance.abort_ability(GameplayAbilityTask.CancelReason.CANCEL_TAG)
				break
#endregion


#region Cooldowns
## Every tag that represents a cooldown for this grant: the definition's own,
## its shared cooldown effects', and any declared explicitly. The one place
## this is computed, so the activation gate and a cooldown-state reading can
## never quietly disagree about what counts as "on cooldown".
static func get_cooldown_tags(spec: GameplayAbilitySpec) -> Array[StringName]:
	var cooldown_tags: Array[StringName] = []
	if spec == null or spec.definition == null:
		return cooldown_tags
	if spec.definition.cooldown_effect != null:
		cooldown_tags.append_array(spec.definition.cooldown_effect.granted_tags)
	for effect: GameplayEffect in spec.definition.shared_cooldown_effects:
		if effect != null:
			cooldown_tags.append_array(effect.granted_tags)
	cooldown_tags.append_array(spec.definition.shared_cooldown_tags)
	return cooldown_tags


## Everything a UI needs to draw one grant's cooldown, read fresh from the
## tags its definition's cooldown effects grant - never from a clock of its
## own, which would part company with the effect the first time it was
## refreshed, removed early, or expired on a turn instead of a second.
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
## Bind an ability to an input slot.
##
## `unbind_others` releases any other granted spec holding that slot, so two
## abilities can never both answer one press.
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
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance) and spec.input_id == input_id:
			instance._input_pressed(owner_asc)


func input_released(input_id: int) -> void:
	_held_inputs.erase(input_id)
	tasks.input_released(input_id)
	for spec: GameplayAbilitySpec in _specs.duplicate():
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance) and spec.input_id == input_id:
			instance._input_released(owner_asc)
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
