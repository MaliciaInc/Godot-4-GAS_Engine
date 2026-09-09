## Granted abilities, the activation gate and input routing.
##
## The registry holds `GameplayAbilitySpec`s, each identified by a
## `GameplayAbilityHandle` rather than the Node underneath it - a handle from
## another ASC can never resolve here by coincidence of a reused id.
## Granting is a two-step transaction: `prepare_ability_grant` instantiates
## and validates once, `commit_prepared_grant`/`discard_prepared_grant`
## register or free it. `give_ability` does both; nothing else validates.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
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
	## Marked for AFTER_ACTIVE_END removal.
	PENDING_REMOVAL,
	## Refused by another spec's block_abilities_query, or a block effect.
	BLOCKED_BY_ACTIVE_ABILITY,
	## Refused by a block somebody outside the ability system asked for -
	## a cutscene, a stun applied by game code, a menu. Distinct from the
	## one above because nothing about the granted abilities explains it,
	## and a UI saying "another ability is blocking this" would be wrong.
	BLOCKED_EXTERNALLY,
}

## remove_ability()'s timing: right away, or once nothing is still running.
enum AbilityRemovalPolicy {
	CANCEL_IMMEDIATELY,
	AFTER_ACTIVE_END,
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

## The canonical try_activate()/give_and_activate_once() entry points.
var lifecycle: AbilityLifecycleRuntime = AbilityLifecycleRuntime.new()

var cooldowns: AbilityCooldownRuntime = AbilityCooldownRuntime.new()

## Finding grants, and the blocks asked for from outside the ability system.
var queries: AbilityQueryRuntime = AbilityQueryRuntime.new()

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


## Registers a validated preparation. Refuses a null/consumed/invalid one, without freeing anything.
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
	# Told before the policies run, and only once the spec resolves by handle:
	# an ability that reacts to being granted may well activate itself, and it
	# has to be able to find itself when it does.
	if spec.per_actor_instance != null:
		spec.per_actor_instance.on_granted()
	# Only now: the spec must resolve by handle before ON_GRANTED/PASSIVE try.
	policies.on_spec_granted(spec)
	if owner_asc != null:
		owner_asc.ability_granted.emit(handle)
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
	var options: GameplayAbilityGrantOptions = GameplayAbilityGrantOptions.new()
	options.level = level
	options.input_id = input_id
	options.source = source
	return give_ability_with_options(scene, options)


## The same grant, said in full.
##
## The action is read off the ability itself when the caller did not name one,
## so an ability that declares which action it answers works without every
## grant repeating it - and a caller that does name one overrules the
## declaration, which is how one ability is given twice on two actions.
func give_ability_with_options(
	scene: PackedScene, options: GameplayAbilityGrantOptions
) -> GameplayAbilityHandle:
	var prepared: PreparedAbilityGrant = prepare_ability_grant(
		scene, options.level, options.input_id, options.source
	)
	if not prepared.validation.is_ok():
		discard_prepared_grant(prepared)
		return GameplayAbilityHandle.new()
	var handle: GameplayAbilityHandle = commit_prepared_grant(prepared)
	var spec: GameplayAbilitySpec = get_spec(handle)
	if spec != null:
		spec.input_action = (
			options.input_action
			if options.input_action != &""
			else spec.definition.input_action
		)
	return handle
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


## CANCEL_IMMEDIATELY aborts and drops the spec now. AFTER_ACTIVE_END defers
## via AbilityInstancingRuntime.mark_pending_removal() - T14's own mechanism.
func remove_ability(
	handle: GameplayAbilityHandle,
	policy: AbilityRuntime.AbilityRemovalPolicy = AbilityRemovalPolicy.CANCEL_IMMEDIATELY
) -> bool:
	var spec: GameplayAbilitySpec = get_spec(handle)
	if spec == null:
		return false
	if policy == AbilityRemovalPolicy.AFTER_ACTIVE_END:
		instancing.mark_pending_removal(spec)
	else:
		_retire(spec)
	return true


## Convenience for AFTER_ACTIVE_END.
func remove_ability_on_end(handle: GameplayAbilityHandle) -> bool:
	return remove_ability(handle, AbilityRemovalPolicy.AFTER_ACTIVE_END)


## Convenience for a caller holding the instance rather than its handle.
func remove(ability: GameplayAbility) -> void:
	if ability == null:
		return
	remove_ability(ability.get_ability_handle())


func _retire(spec: GameplayAbilitySpec, request_reevaluation: bool = true) -> void:
	# First: a reevaluation reentered from an abort below must see
	# PENDING_REMOVAL and never restart what this is tearing down.
	spec.pending_remove = true
	var instance: GameplayAbility = spec.per_actor_instance
	if instance != null and is_instance_valid(instance):
		# Told before anything is severed, so it can still reach what it owns.
		instance.on_removed()
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
	if request_reevaluation:
		policies.request_reevaluation()


## Abort every running ability, for cleanup - PER_ACTOR stays idle after,
## PER_EXECUTION has no idle state so aborting frees it too, same as an end.
func abort_all(
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED
) -> void:
	# A passive aborted below must not restart mid-loop - see begin_suspension().
	policies.begin_suspension()
	for spec: GameplayAbilitySpec in _specs.duplicate():
		var instance: GameplayAbility = spec.per_actor_instance
		if instance != null and is_instance_valid(instance) and instance.is_active:
			instance.abort_ability(reason)
		for execution: GameplayAbility in spec.active_instances.duplicate():
			if is_instance_valid(execution) and execution.is_active:
				execution.abort_ability(reason)
	tasks.cancel_all(reason)
	policies.end_suspension()
	# ASC_CLEANUP: everything is about to be cleared, never reevaluated.
	if reason != GameplayAbilityTask.CancelReason.ASC_CLEANUP:
		policies.request_reevaluation()


func clear() -> void:
	policies.begin_suspension()
	for spec: GameplayAbilitySpec in _specs.duplicate():
		_retire(spec, false)
	tasks.cancel_all(GameplayAbilityTask.CancelReason.ASC_CLEANUP)
	_specs.clear()
	_specs_by_id.clear()
	_held_inputs.clear()
	policies.end_suspension()


## Terminal teardown. Unlike clear(), this object is not reusable afterwards.
func dispose() -> void:
	clear()

	tasks.owner_asc = null

	instancing.owner_asc = null
	instancing.ability_runtime = null

	tag_semantics.owner_asc = null
	tag_semantics.ability_runtime = null

	policies.unbind()
	policies.ability_runtime = null
	lifecycle.ability_runtime = null
	cooldowns.ability_runtime = null
	queries.ability_runtime = null

	owner_asc = null
	tags = null
#endregion


#region Activation gate
## Whether a spec may activate, and why not - a reason, not a bare bool.
func activation_error(spec: GameplayAbilitySpec) -> AbilityRuntime.ActivationError:
	if spec == null or spec.definition == null:
		return ActivationError.INTERNAL_ERROR
	if spec.pending_remove:
		return ActivationError.PENDING_REMOVAL
	# Before cost and cooldown: a caller told "you cannot afford it" while a
	# cutscene is what is really stopping them would go and find the money.
	if queries.blocked_externally(spec):
		return ActivationError.BLOCKED_EXTERNALLY
	# PER_EXECUTION keeps per_actor_instance null by construction, never refused here.
	var instance: GameplayAbility = spec.per_actor_instance
	if (
		instance != null
		and instance.is_active
		and not spec.definition.retrigger_while_active
	):
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
	# After the ability's own declaration, never instead of it: the table adds
	# restrictions and can never turn a refusal into an allow.
	var by_relationship: ActivationError = _relationship_refusal(spec)
	if by_relationship != ActivationError.NONE:
		return by_relationship
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


## What the component's relationship table says about this grant, if it has one.
func _relationship_refusal(spec: GameplayAbilitySpec) -> ActivationError:
	if owner_asc == null or owner_asc.ability_tag_relationships == null:
		return ActivationError.NONE
	return owner_asc.ability_tag_relationships.refusal_for(
		effective_ability_tags(spec), tags
	)


## Public: AbilityActivationPolicyRuntime needs the same check.
static func query_matches_runtime(query: GameplayTagQuery, runtime: GameplayTagRuntime) -> bool:
	return query != null and not query.is_empty() and query.matches_runtime(runtime)


## Whether whoever caused this activation qualifies for the spec's source
## gates.
##
## Read from the event's own snapshot rather than from the world: the
## instigator's tags are what they were when the event was sent, and an
## activation that arrives three frames later is about that moment. An event
## with no tags on it does not invent any, so a non-empty required query
## refuses rather than passing by default.
##
## No new refusal reasons: a blocked source is BLOCKED_TAG and a missing one
## is MISSING_TAG, which is what they are.
func source_gate_error(
	spec: GameplayAbilitySpec, event: GameplayEventData
) -> AbilityRuntime.ActivationError:
	if spec == null or spec.definition == null or event == null:
		return ActivationError.NONE
	var blocked: GameplayTagQuery = spec.definition.source_blocked_query
	var required: GameplayTagQuery = spec.definition.source_required_query
	var carried: Array[StringName] = event.instigator_tags
	if blocked != null and not blocked.is_empty() and blocked.matches_tags(carried):
		return ActivationError.BLOCKED_TAG
	if required != null and not required.is_empty() and not required.matches_tags(carried):
		return ActivationError.MISSING_TAG
	return ActivationError.NONE


func can_activate(spec: GameplayAbilitySpec) -> bool:
	return activation_error(spec) == ActivationError.NONE


## The same answer, with the refusal announced.
##
## `named` is the instance a refusal is reported against. Null means the spec's
## own, which is what an activation nobody is holding an instance for reports;
## a caller that handed one in gets that one back, because the instance it asked
## about is the instance it is waiting to hear about.
func can_activate_spec(
	spec: GameplayAbilitySpec,
	named: GameplayAbility = null,
	announce_refusal: bool = false
) -> bool:
	if spec == null:
		return false
	var reason: AbilityRuntime.ActivationError = activation_error(spec)
	if reason == ActivationError.NONE:
		return true
	if announce_refusal and owner_asc != null:
		owner_asc.ability_activation_failed.emit(
			named if named != null else spec.per_actor_instance, reason
		)
	return false


## See AbilityActivationPolicyRuntime.request_reevaluation().
func request_passive_reevaluation() -> void:
	policies.request_reevaluation()


## See AbilityActivationPolicyRuntime.reevaluate().
func reevaluate_passives() -> void:
	policies.reevaluate()


## See AbilityActivationPolicyRuntime.active_requirements_error().
func active_requirements_error(spec: GameplayAbilitySpec) -> AbilityRuntime.ActivationError:
	return policies.active_requirements_error(spec)


## The canonical activation entry point - input, event routing and passives
## all call this by handle. See AbilityLifecycleRuntime.try_activate().
## Activate because this event happened, carrying the event with it.
func try_activate_from_event(
	handle: GameplayAbilityHandle, event: GameplayEventData
) -> GameplayAbilityActivationResult:
	return lifecycle.try_activate_from_event(handle, event)


func try_activate(
	handle: GameplayAbilityHandle, context: GameplayEffectContext = null
) -> GameplayAbilityActivationResult:
	return lifecycle.try_activate(handle, context)


## The one activation path. See AbilityLifecycleRuntime.try_activate_with().
func try_activate_with(
	handle: GameplayAbilityHandle, activation: GameplayAbilityActivationContext
) -> GameplayAbilityActivationResult:
	return lifecycle.try_activate_with(handle, activation)


## See AbilityLifecycleRuntime.give_and_activate_once().
func give_and_activate_once(
	scene: PackedScene,
	level: float = 1.0,
	source: GameplayAbilitySource = null,
	context: GameplayEffectContext = null
) -> GameplayAbilityActivationResult:
	return lifecycle.give_and_activate_once(scene, level, source, context)


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
## See AbilityCooldownRuntime.get_cooldown_tags().
static func get_cooldown_tags(spec: GameplayAbilitySpec) -> Array[StringName]:
	return AbilityCooldownRuntime.get_cooldown_tags(spec)


## See AbilityCooldownRuntime.get_ability_cooldown_state().
func get_ability_cooldown_state(handle: GameplayAbilityHandle) -> AbilityCooldownState:
	return cooldowns.get_ability_cooldown_state(handle)
#endregion


#region Input routing
## `unbind_others` releases any other spec holding the slot already.
## Route an input slot to a granted spec, which is what a binding is about:
## the grant answers the press, whether or not anything is running right now.
func bind_spec_to_input(
	bound: GameplayAbilitySpec, input_id: int, unbind_others: bool = true
) -> bool:
	if bound == null or not _specs.has(bound):
		push_error("GAS_Engine: cannot bind an ability that was never granted to this ASC.")
		return false

	if unbind_others:
		for spec: GameplayAbilitySpec in _specs:
			if spec != bound and spec.input_id == input_id:
				spec.input_id = -1

	bound.input_id = input_id
	return true


## Convenience for a caller holding the instance rather than its handle.
func bind_to_input(ability: GameplayAbility, input_id: int, unbind_others: bool = true) -> bool:
	var bound: GameplayAbilitySpec = ability.current_spec if ability != null else null
	return bind_spec_to_input(bound, input_id, unbind_others)


## As a copy: a caller clearing this must not leave the runtime believing nothing is pressed.
func held_inputs() -> Array[int]:
	return _held_inputs.duplicate()


## An action was pressed, by name.
##
## The same rules as a slot: the grants are snapshotted first, because a
## sibling granted by this very press must not also receive it.
func input_action_pressed(action: StringName) -> void:
	_route_action(action, true)


func input_action_released(action: StringName) -> void:
	_route_action(action, false)


func _route_action(action: StringName, pressed: bool) -> void:
	if action == &"":
		return
	for spec: GameplayAbilitySpec in _specs.duplicate():
		if spec.input_action != action:
			continue
		if pressed:
			_deliver_input(
				spec,
				func(a: GameplayAbility) -> void: a._input_pressed(owner_asc),
				func(a: GameplayAbility) -> void: a._active_input_pressed(owner_asc)
			)
		else:
			_deliver_input(
				spec,
				func(a: GameplayAbility) -> void: a._input_released(owner_asc),
				func(a: GameplayAbility) -> void: a._active_input_released(owner_asc)
			)


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
