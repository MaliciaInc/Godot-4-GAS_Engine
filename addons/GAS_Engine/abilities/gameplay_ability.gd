## One granted ability: activation rules, cost/cooldown, and the logic a
## subclass overrides. Event payload is typed, unlike upstream's Variant.
##
## @meta_addon: GAS_Engine
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayAbility extends Node


## PER_ACTOR: one instance for the grant's lifetime, second activation
## refused while running. PER_EXECUTION: one instance per activation.
enum InstancingPolicy {
	PER_ACTOR,
	PER_EXECUTION,
}

## MANUAL: input/explicit call. ON_GRANTED: tries once, never auto-retries.
## ON_GAMEPLAY_EVENT: gameplay_event_triggers decide. PASSIVE: continuously
## reevaluated - see AbilityActivationPolicyRuntime.
enum ActivationPolicy {
	MANUAL,
	ON_GRANTED,
	ON_GAMEPLAY_EVENT,
	PASSIVE,
}

signal ability_ended(was_cancelled: bool)

@export_category("Ability Rules")
@export var ability_name: String = ""

## Frozen at grant time, same as instancing_policy.
@export var activation_policy: GameplayAbility.ActivationPolicy = ActivationPolicy.MANUAL

## Identity, not activation gating - effective tags are these plus dynamic_tags.
@export var ability_tags: Array[StringName] = []

## Read once at grant time into the frozen definition - editing after does nothing.
@export var instancing_policy: GameplayAbility.InstancingPolicy = InstancingPolicy.PER_ACTOR

@export var ability_level: float = 1.0

## Empty/null imposes no requirement.
@export var activation_required_query: GameplayTagQuery = null
@export var activation_blocked_query: GameplayTagQuery = null

## Granted once on active_count 0->1, retired once on 1->0 - never per PER_EXECUTION instance.
@export var activation_owned_tags: Array[StringName] = []

## On successful activation, other granted specs matching this are cancelled - not this one unless allow_self_cancel.
@export var cancel_abilities_query: GameplayTagQuery = null
@export var allow_self_cancel: bool = false

## While active_count > 0, blocks a matching new activation (BLOCKED_BY_ACTIVE_ABILITY, not BLOCKED_TAG).
@export var block_abilities_query: GameplayTagQuery = null

## Gates accepts_target() - see apply_effect_to_targets(), the sole enforcement route.
@export var target_required_query: GameplayTagQuery = null
@export var target_blocked_query: GameplayTagQuery = null

@export_category("Ability Mechanics")
## Every priced entry this charges. Empty means free; resolved once at commit.
@export var costs: Array[GameplayAbilityCost] = []
@export var cooldown_effect: GameplayEffect
@export var shared_cooldown_effects: Array[GameplayEffect] = []
@export var shared_cooldown_tags: Array[StringName] = []

@export_category("Ability Triggers")
## Only consulted for ON_GAMEPLAY_EVENT - any one matching trigger wakes this.
@export var gameplay_event_triggers: Array[GameplayAbilityEventTrigger] = []

@export_category("Input Routing")
## The input slot this ability answers, or -1 when unbound.
@export var input_id: int = -1

## The context of the activation currently running. Null when idle.
var current_context: GameplayEffectContext = null

var owner_asc: AbilitySystemComponent = null

## Null until granted; once set, read level/input through the accessors below.
var current_spec: GameplayAbilitySpec = null

var is_active: bool = false

## Whether this activation has already paid. One activation charges once.
var _committed: bool = false

var _reported_drift: bool = false

## What _run_activation() resolved to - read after try_activate() awaits `ability_ended`.
var _last_activation_succeeded: bool = false


#region Spec accessors
## current_spec once granted; the exported default for an uncommitted probe.
func get_ability_level() -> float:
	return current_spec.level if current_spec != null else ability_level


func get_input_id() -> int:
	return current_spec.input_id if current_spec != null else input_id


## Null when this instance was never granted through the grant pipeline.
func get_ability_handle() -> GameplayAbilityHandle:
	return current_spec.handle if current_spec != null else null
#endregion


#region Execution
## Compat: blocks until this finishes, unlike AbilityRuntime.try_activate().
func try_activate(context: GameplayEffectContext = null) -> bool:
	if is_active or owner_asc == null:
		return false
	if not owner_asc.can_activate_ability(self, true):
		return false
	_begin_runtime_activation(context)
	if is_active:
		await ability_ended
	return _last_activation_succeeded


## Registers active state, starts _run_activation() without awaiting.
func _begin_runtime_activation(context: GameplayEffectContext) -> void:
	is_active = true
	if current_spec != null:
		current_spec.active_count += 1
		if current_spec.active_count == 1:
			_set_activation_owned_tags(true)
		owner_asc.ability_runtime.request_passive_reevaluation()
	current_context = context
	_cancel_conflicting_abilities()
	_run_activation()


func _run_activation() -> void:
	# `await` hands a coroutine's value back untyped - a channelled ability
	# crashed on resume with an Object where a bool belonged.
	var outcome: Variant = await _activate_ability()
	var success: bool = outcome is bool and outcome
	_last_activation_succeeded = success

	# Only close if the subclass hasn't already, so `ability_ended` fires once.
	if is_active:
		end_ability(not success)
	current_context = null


## Pay cost and start cooldowns as one transaction, called from
## `_activate_ability` once committed - all-or-nothing, no cues/events by
## contract, so a rollback leaves nothing observable.
func commit_ability() -> AbilityCommitResult:
	var result: AbilityCommitResult = AbilityCommitResult.new()
	if owner_asc == null:
		result.status = AbilityCommitResult.Status.OWNER_MISSING
		return result
	if _committed:
		result.status = AbilityCommitResult.Status.ALREADY_COMMITTED
		return result

	# The snapshot froze this ability's authoring, so it is what can tell when
	# this instance stopped agreeing with it. Said once: it is a wiring mistake.
	if not _reported_drift:
		_reported_drift = GameplayAbilityDefinitionSnapshot.report_drift(
			self, current_spec.definition)

	# current_spec is guaranteed non-null. Every step after reads
	# resolved.absolute_effect, never the definition's costs again.
	var resolved: GameplayResolvedCost = GameplayAbilityCostResolver.resolve(
		current_spec.definition.costs, owner_asc, current_spec.level
	)
	result.resolved_cost = resolved
	if (
		resolved.status != GameplayResolvedCost.Status.OK
		and resolved.status != GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES
	):
		result.status = AbilityCommitResult.Status.INVALID_COST_DEFINITION
		return result
	# Self-check against the resolver's own output - a violation means it is broken.
	if not AbilityCommitContract.is_reversible_charge(resolved.absolute_effect, 1.0):
		result.status = AbilityCommitResult.Status.INVALID_COST_DEFINITION
		return result

	var cooldowns: Array[GameplayEffect] = AbilityCommitContract.unique_cooldowns(
		current_spec.definition.cooldown_effect, current_spec.definition.shared_cooldown_effects
	)
	for cooldown: GameplayEffect in cooldowns:
		if not AbilityCommitContract.is_legal_cooldown(cooldown):
			result.status = AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION
			return result

	# Asked before anything applies, so it never starts a cooldown unpaid.
	if resolved.status == GameplayResolvedCost.Status.INSUFFICIENT_RESOURCES:
		result.status = AbilityCommitResult.Status.INSUFFICIENT_RESOURCES
		return result

	for cooldown: GameplayEffect in cooldowns:
		var started: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			cooldown, owner_asc, current_spec.level
		)
		if started == null:
			_roll_back(result)
			result.status = AbilityCommitResult.Status.COOLDOWN_APPLICATION_FAILED
			return result
		result.applied_cooldowns.append(started)

	# Re-asked here, not trusted from resolve time - a cooldown's signals can
	# let a listener move the resources about to be taken.
	if (
		resolved.absolute_effect != null
		and not owner_asc.can_afford_cost(resolved.absolute_effect, 1.0)
	):
		_roll_back(result)
		result.status = AbilityCommitResult.Status.RESOURCES_CHANGED_DURING_COMMIT
		return result

	if resolved.absolute_effect != null:
		var charged: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			resolved.absolute_effect, owner_asc, 1.0
		)
		if charged == null:
			_roll_back(result)
			result.status = AbilityCommitResult.Status.COST_APPLICATION_FAILED
			return result
		result.applied_cost = charged

	_committed = true
	result.status = AbilityCommitResult.Status.SUCCESS
	return result


## Undo cooldowns a failed commit already started; emptied too, so the result reports nothing applied.
func _roll_back(result: AbilityCommitResult) -> void:
	for started: ActiveGameplayEffect in result.applied_cooldowns:
		owner_asc.remove_active_effect(started)
	result.applied_cooldowns.clear()


## Override this. The default succeeds immediately.
func _activate_ability() -> bool:
	return true


## Interrupt mid-cast.
func abort_ability(
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ABORTED
) -> void:
	if is_active:
		end_ability(true, reason)


## Stays granted: ending is not un-granting. `is_active` clears first, since
## cancelling a task can resume a coroutine that would otherwise double-emit.
## Wait until this ability is done, and return at once if it already is.
##
## `try_activate()` returns when activation BEGINS, so an ability that refuses -
## or has nothing to do - has already ended by the time a caller sees the
## result, and awaiting `ability_ended` then waits for what will not fire
## again. The counterpart of `GameplayAbilityTask.completed()`.
func completed() -> void:
	if not is_active:
		return
	await ability_ended


func end_ability(
	was_cancelled: bool = false,
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ENDED
) -> void:
	if not is_active:
		return
	is_active = false
	if current_spec != null:
		current_spec.active_count = maxi(current_spec.active_count - 1, 0)
		if current_spec.active_count == 0:
			_set_activation_owned_tags(false)
	if owner_asc != null:
		owner_asc.cancel_ability_tasks(self, reason)
		owner_asc.ability_runtime.request_passive_reevaluation()
		if current_spec != null:
			owner_asc.ability_runtime_ended.emit(current_spec.handle, self, was_cancelled, reason)
	# The one place a commit is forgotten - two owners for one transition otherwise.
	_committed = false
	ability_ended.emit(was_cancelled)


## See AbilityTagSemanticsRuntime.set_activation_owned_tags.
func _set_activation_owned_tags(grant: bool) -> void:
	if owner_asc == null:
		return
	owner_asc.ability_runtime.tag_semantics.set_activation_owned_tags(current_spec, grant)


## See AbilityTagSemanticsRuntime.cancel_conflicting_abilities.
func _cancel_conflicting_abilities() -> void:
	if owner_asc == null:
		return
	owner_asc.ability_runtime.tag_semantics.cancel_conflicting_abilities(current_spec)
#endregion


#region Helpers
## Play a cue on the owning entity.
func execute_cue(tag: StringName) -> void:
	if owner_asc == null:
		return
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = tag
	params.instigator = owner_asc.get_effect_target()
	params.target = owner_asc.get_effect_target()
	owner_asc.execute_cue(params)


## Reads the frozen snapshot's target_required/blocked_query, immune to edits.
func accepts_target(target_asc: AbilitySystemComponent) -> bool:
	if target_asc == null or current_spec == null or current_spec.definition == null:
		return false
	var required: GameplayTagQuery = current_spec.definition.target_required_query
	if required != null and not required.is_empty() and not required.matches_runtime(target_asc.tags):
		return false
	var blocked: GameplayTagQuery = current_spec.definition.target_blocked_query
	if blocked != null and not blocked.is_empty() and blocked.matches_runtime(target_asc.tags):
		return false
	return true


## Each target gets its own spec copy - sharing one across an AoE let target
## A's evaluation change what target B received.
func apply_effect_to_targets(
	effect_res: GameplayEffect, target_data: GameplayAbilityTargetData
) -> GameplayTargetApplicationResult:
	var result: GameplayTargetApplicationResult = GameplayTargetApplicationResult.new()
	if effect_res == null or target_data == null or owner_asc == null:
		return result

	# Instigator/causer are the persistent avatar - `self` would dangle once
	# the ability ends.
	var avatar: Node = owner_asc.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(avatar, avatar)
	context.target_data = target_data
	context.ability_handle = get_ability_handle()
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect_res, context, get_ability_level())
	var reached: Array[int] = []
	var unreachable: Array[int] = []
	for target: Node in target_data.get_target_nodes():
		if target == null:
			continue
		result.attempted_targets += 1

		var target_asc: AbilitySystemComponent = find_asc_on(target)
		if target_asc == null:
			if not unreachable.has(target.get_instance_id()):
				unreachable.append(target.get_instance_id())
				result.missing_asc_targets.append(target)
			continue

		# Two colliders on one actor are one target - twice would double an
		# AoE for anything with two hitboxes.
		if reached.has(target_asc.get_instance_id()):
			continue
		reached.append(target_asc.get_instance_id())

		# Sole enforcement route for target_required/blocked_query.
		if not accepts_target(target_asc):
			result.rejected_targets.append(target_asc)
			continue

		var applied: GameplayEffectApplicationResult = (
			owner_asc.apply_effect_spec_to_target_result(spec, target_asc)
		)
		result.applications.append(applied)
		if not applied.is_ok():
			result.rejected_targets.append(target_asc)
			continue
		result.applied_targets.append(target_asc)
		result.applied_effects.append(applied.active_effect)
	return result


## The ability system a node belongs to - no algorithm of its own, one search.
static func find_asc_on(node: Node) -> AbilitySystemComponent:
	return AbilitySystemLocator.find_for_node(node)


## Convenience wrapper - the implementation lives on AbilityRuntime, keyed by spec.
func get_cooldown_tags() -> Array[StringName]:
	return AbilityRuntime.get_cooldown_tags(current_spec)


## Everything a UI needs, read fresh. Live-instance wrapper; AbilityRuntime answers by handle.
func get_cooldown_state() -> AbilityCooldownState:
	if owner_asc == null or current_spec == null:
		return AbilityCooldownState.new()
	return owner_asc.ability_runtime.get_ability_cooldown_state(current_spec.handle)
#endregion


#region Input Routing
## The bound input was pressed.
func _input_pressed(asc: AbilitySystemComponent) -> void:
	if is_active:
		_active_input_pressed(asc)
		return
	if owner_asc != null:
		owner_asc.ability_runtime.try_activate(get_ability_handle())


## The bound input was released.
func _input_released(asc: AbilitySystemComponent) -> void:
	if is_active:
		_active_input_released(asc)


## Pressed while running. Override for "press again to cancel/detonate".
func _active_input_pressed(_asc: AbilitySystemComponent) -> void:
	pass


## Released while running. Override for "hold to charge, release to fire".
func _active_input_released(_asc: AbilitySystemComponent) -> void:
	pass
#endregion


#region Task factories
## Null when there is no ASC - a task nobody owns could never be cancelled.
func _own(task: GameplayAbilityTask) -> GameplayAbilityTask:
	if task == null or owner_asc == null:
		return null
	return owner_asc.register_ability_task(task)


func wait_delay(seconds: float) -> AbilityTaskWaitDelay:
	return _own(AbilityTaskWaitDelay.create(self, seconds)) as AbilityTaskWaitDelay


## `-1` means this ability's own bound slot. Resolved in the body, not a
## default parameter value: that would freeze `input_id` at parse time.
func wait_input_pressed(input_slot: int = -1) -> AbilityTaskWaitInput:
	return _wait_input(input_slot, AbilityTaskWaitInput.Transition.PRESSED)


func wait_input_released(input_slot: int = -1) -> AbilityTaskWaitInput:
	return _wait_input(input_slot, AbilityTaskWaitInput.Transition.RELEASED)


func _wait_input(
	input_slot: int, transition: AbilityTaskWaitInput.Transition
) -> AbilityTaskWaitInput:
	var slot: int = get_input_id() if input_slot == -1 else input_slot
	return _own(AbilityTaskWaitInput.create(self, slot, transition)) as AbilityTaskWaitInput


func wait_gameplay_event(tag: StringName) -> AbilityTaskWaitGameplayEvent:
	var task: GameplayAbilityTask = _own(AbilityTaskWaitGameplayEvent.create(self, tag))
	return task as AbilityTaskWaitGameplayEvent


func wait_target_data() -> AbilityTaskWaitTargetData:
	return _own(AbilityTaskWaitTargetData.create(self)) as AbilityTaskWaitTargetData


## Answer this ability's own request for targets.
func submit_target_data(data: GameplayAbilityTargetData) -> void:
	if owner_asc != null:
		owner_asc.submit_ability_target_data(self, data)
#endregion
