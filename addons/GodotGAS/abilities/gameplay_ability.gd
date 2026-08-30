## One granted ability: its activation rules, its cost and cooldown, and the
## logic a subclass overrides.
##
## The event payload is a typed GameplayEffectContext. Upstream stored a
## `Variant` documented as "a GameplayEffectSpec, a Dictionary, or a Node", so
## every subclass had to guess which, and a wrong guess read as null rather than
## failing.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayAbility extends Node


## PER_ACTOR: one instance lives for as long as the grant does, and a second
## activation while it is running is refused. PER_EXECUTION: every activation
## gets its own instance, so several casts of the same ability can run at
## once. Unreal's NonInstanced is not implemented here: it depends on sharing
## a CDO, which has no Godot equivalent and buys no demonstrated advantage
## over the risk of accidental global state.
enum InstancingPolicy {
	PER_ACTOR,
	PER_EXECUTION,
}

signal ability_ended(was_cancelled: bool)

@export_category("Ability Rules")
@export var ability_name: String = ""

## Identifies this ability, e.g. Ability.Fireball.
@export var ability_tag: StringName = &"Ability.None"

## How AbilityRuntime creates the instance that actually runs this ability.
## Read once at grant time into the spec's frozen definition - changing it on
## a Node after that grant changes nothing already running.
@export var instancing_policy: InstancingPolicy = InstancingPolicy.PER_ACTOR

@export var ability_level: float = 1.0

## The ASC must have none of these for the ability to activate.
@export var activation_blocked_tags: Array[StringName] = []

## The ASC must have all of these for the ability to activate.
@export var activation_required_tags: Array[StringName] = []

@export_category("Ability Mechanics")
## Every priced entry this ability charges. Empty means free. Resolved as
## one frozen, aggregated charge at commit time by
## GameplayAbilityCostResolver - never a hand-authored GameplayEffect.
@export var costs: Array[GameplayAbilityCost] = []
@export var cooldown_effect: GameplayEffect
@export var shared_cooldown_effects: Array[GameplayEffect] = []
@export var shared_cooldown_tags: Array[StringName] = []

@export_category("Ability Triggers")
## The event tag that wakes this ability. Hierarchical: a listener on
## `Event.Damage` also receives `Event.Damage.Critical`.
@export var trigger_event_tag: StringName = &""

@export_category("Input Routing")
## The input slot this ability answers, or -1 when unbound.
@export var input_id: int = -1

## The context of the activation currently running. Null when idle.
var current_context: GameplayEffectContext = null

var owner_asc: AbilitySystemComponent = null

## What this instance was granted as. Null until AbilityRuntime's grant
## pipeline assigns it, and the source of truth for level and input once it
## does: ability_level and input_id above stay the authoring surface a scene
## edits, but core logic reads through the accessors below instead.
var current_spec: GameplayAbilitySpec = null

var is_active: bool = false

## Whether this activation has already paid. One activation charges once.
var _committed: bool = false


#region Spec accessors
## The level this grant runs at. current_spec once granted; the exported
## default otherwise, for a probe not yet committed to a spec.
func get_ability_level() -> float:
	return current_spec.level if current_spec != null else ability_level


func get_input_id() -> int:
	return current_spec.input_id if current_spec != null else input_id


## Null when this instance was never granted through the grant pipeline.
func get_ability_handle() -> GameplayAbilityHandle:
	return current_spec.handle if current_spec != null else null
#endregion


#region Execution
## Try to run this ability. Returns whether it actually ran.
func try_activate(context: GameplayEffectContext = null) -> bool:
	if is_active or owner_asc == null:
		return false
	if not owner_asc.can_activate_ability(self, true):
		return false

	is_active = true
	if current_spec != null:
		current_spec.active_count += 1
	current_context = context

	# `await` on a coroutine hands the value back untyped, and the declared
	# type of the local does not convert it: a channelled ability - one that
	# suspends inside _activate_ability - reached end_ability with an Object
	# where a bool belonged and crashed on resume. Taken explicitly instead.
	var outcome: Variant = await _activate_ability()
	var success: bool = outcome is bool and outcome

	# The subclass may already have ended the ability; only close it if it did
	# not, so `ability_ended` fires exactly once.
	if is_active:
		end_ability(not success)

	current_context = null
	return success


## Pay the cost and start the cooldowns as one transaction.
##
## Call this from `_activate_ability` the moment the ability is committed, so a
## cancelled cast has not already charged the player.
##
## Either the whole price is taken or none of it is. A cooldown that fails to
## apply retires the cooldowns already started; a cost that fails retires all of
## them. Costs and cooldowns carry no cues and no events by contract, so a
## rollback leaves nothing anyone could have observed.
func commit_ability() -> AbilityCommitResult:
	var result: AbilityCommitResult = AbilityCommitResult.new()
	if owner_asc == null:
		result.status = AbilityCommitResult.Status.OWNER_MISSING
		return result
	if _committed:
		result.status = AbilityCommitResult.Status.ALREADY_COMMITTED
		return result

	# current_spec is guaranteed non-null here: the one place that sets
	# owner_asc (AbilityRuntime.commit_prepared_grant) always sets both
	# together. Costs/cooldowns are read from the frozen definition, never
	# from this Node's own exports, which are authoring surface only once
	# a spec exists.
	# The only place a percentage is computed. Every step after this reads
	# resolved.absolute_effect - never the definition's costs again - so
	# nothing here can recalculate a percentage mid-commit.
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
	# A self-check against the resolver's own output, not against authoring:
	# nothing but the resolver builds this effect. A violation here can only
	# mean the resolver is broken.
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

	# Asked before anything is applied, so an ability nobody can afford does
	# not start a cooldown it never paid for.
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

	# The charge goes last, and is asked again here rather than trusted from
	# resolve time: applying a cooldown grants tags and emits signals, and a
	# synchronous listener can move the very resources the charge is about to
	# take. The percentage stays frozen - this recomputes affordability
	# against the same resolved.absolute_effect, never a percentage.
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


## Undo the cooldowns a failed commit had already started.
##
## The list is emptied as well as retired: a result that failed reports nothing
## applied, because after this nothing is.
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


## Close the ability. It stays granted: ending is not un-granting.
##
## Idempotent, and the order below is load-bearing. `is_active` is cleared
## first because cancelling a task can resume a coroutine that awaited it, and
## that coroutine arriving here again would emit `ability_ended` a second time.
## Finding the ability already closed, it returns instead.
func end_ability(
	was_cancelled: bool = false,
	reason: GameplayAbilityTask.CancelReason = GameplayAbilityTask.CancelReason.ABILITY_ENDED
) -> void:
	if not is_active:
		return
	is_active = false
	if current_spec != null:
		current_spec.active_count = maxi(current_spec.active_count - 1, 0)
	if owner_asc != null:
		owner_asc.cancel_ability_tasks(self, reason)
	# The one place a commit is forgotten. `try_activate` deliberately does not
	# clear it as well: an idle ability holds `_committed == false` as an
	# invariant, and resetting at both ends gives one transition two owners.
	_committed = false
	ability_ended.emit(was_cancelled)
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


## Build a spec from an effect and fire it at every target, and say what came
## of it.
##
## Each target receives its own spec copy, made by
## `apply_effect_spec_to_target`. Sharing one spec across an AoE let target A's
## evaluation change what target B received.
##
## A result comes back even for arguments that were never usable, so a caller
## never has to distinguish null from nothing-happened.
func apply_effect_to_targets(
	effect_res: GameplayEffect, target_data: GameplayAbilityTargetData
) -> GameplayTargetApplicationResult:
	var result: GameplayTargetApplicationResult = GameplayTargetApplicationResult.new()
	if effect_res == null or target_data == null or owner_asc == null:
		return result

	# The instigator and causer are both the persistent avatar. Passing `self`
	# would name a transient node as the cause and leave a dangling reference
	# once the ability ends.
	var avatar: Node = owner_asc.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(avatar, avatar)
	context.target_data = target_data

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

		# Two colliders on one actor are one target. Applying twice would
		# double an AoE for anything that happens to have two hitboxes.
		if reached.has(target_asc.get_instance_id()):
			continue
		reached.append(target_asc.get_instance_id())

		var applied: ActiveGameplayEffect = owner_asc.apply_effect_spec_to_target(
			spec, target_asc
		)
		if applied == null:
			result.rejected_targets.append(target_asc)
			continue
		result.applied_targets.append(target_asc)
		result.applied_effects.append(applied)
	return result


## The ability system a node belongs to.
##
## Kept as a public method because callers use it, but it owns no algorithm:
## the search lives in one place so a change to how an ASC is found cannot
## apply here and not there.
static func find_asc_on(node: Node) -> AbilitySystemComponent:
	return AbilitySystemLocator.find_for_node(node)


## Every tag that represents a cooldown for this ability: its own, those of
## the shared cooldown effects, and any declared explicitly.
##
## A convenience wrapper: the one implementation lives on AbilityRuntime,
## keyed by spec, so a tool that only has a handle gets the same answer
## without needing a live instance.
func get_cooldown_tags() -> Array[StringName]:
	return AbilityRuntime.get_cooldown_tags(current_spec)


## Everything a UI needs to draw this ability's cooldown, read fresh.
##
## A convenience wrapper for when a live instance is at hand; the runtime
## answers the same question by handle, so a tool that lost the Node but
## kept the handle can still ask.
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
	try_activate()


## The bound input was released.
func _input_released(asc: AbilitySystemComponent) -> void:
	if is_active:
		_active_input_released(asc)


## Pressed while already running. Override for "press again to cancel" or
## "press again to detonate".
func _active_input_pressed(_asc: AbilitySystemComponent) -> void:
	pass


## Released while already running. Override for "hold to charge, release to
## fire".
func _active_input_released(_asc: AbilitySystemComponent) -> void:
	pass
#endregion


#region Task factories
## Hand a freshly built task to the ASC that will own it.
##
## Null when there is no ASC. A task nobody owns is worse than no task: the
## ability would suspend on something that nothing can ever cancel, and no
## teardown path would reach it.
func _own(task: GameplayAbilityTask) -> GameplayAbilityTask:
	if task == null or owner_asc == null:
		return null
	return owner_asc.register_ability_task(task)


func wait_delay(seconds: float) -> AbilityTaskWaitDelay:
	return _own(AbilityTaskWaitDelay.create(self, seconds)) as AbilityTaskWaitDelay


## Wait for a press. `-1` means this ability's own bound slot; any other value
## is used as given.
##
## Resolved in the body rather than written as a default parameter value: a
## default is evaluated against the class, so it would freeze whatever
## `input_id` held at parse time instead of what it holds at the call.
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
