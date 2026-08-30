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


signal ability_ended(was_cancelled: bool)

@export_category("Ability Rules")
@export var ability_name: String = ""

## Identifies this ability, e.g. Ability.Fireball.
@export var ability_tag: StringName = &"Ability.None"

@export var ability_level: float = 1.0

## The ASC must have none of these for the ability to activate.
@export var activation_blocked_tags: Array[StringName] = []

## The ASC must have all of these for the ability to activate.
@export var activation_required_tags: Array[StringName] = []

@export_category("Ability Mechanics")
@export var cost_effect: GameplayEffect
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

var is_active: bool = false

## Whether this activation has already paid. One activation charges once.
var _committed: bool = false


#region Initialization
func _ready() -> void:
	if owner_asc != null:
		return
	var parent: Node = get_parent()
	var parent_asc: AbilitySystemComponent = parent as AbilitySystemComponent
	if parent_asc != null:
		parent_asc.grant_ability(self)
#endregion


#region Execution
## Try to run this ability. Returns whether it actually ran.
func try_activate(context: GameplayEffectContext = null) -> bool:
	if is_active or owner_asc == null:
		return false
	if not owner_asc.can_activate_ability(self, true):
		return false

	is_active = true
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
	if not _validate_cost_definition(cost_effect):
		result.status = AbilityCommitResult.Status.INVALID_COST_DEFINITION
		return result

	var cooldowns: Array[GameplayEffect] = _unique_cooldown_effects()
	for cooldown: GameplayEffect in cooldowns:
		if not _validate_cooldown_definition(cooldown):
			result.status = AbilityCommitResult.Status.INVALID_COOLDOWN_DEFINITION
			return result

	# Asked before anything is applied, so an ability nobody can afford does
	# not start a cooldown it never paid for.
	if not owner_asc.can_afford_cost(cost_effect, ability_level):
		result.status = AbilityCommitResult.Status.INSUFFICIENT_RESOURCES
		return result

	for cooldown: GameplayEffect in cooldowns:
		var started: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			cooldown, owner_asc, ability_level
		)
		if started == null:
			_roll_back(result)
			result.status = AbilityCommitResult.Status.COOLDOWN_APPLICATION_FAILED
			return result
		result.applied_cooldowns.append(started)

	# The charge goes last: it is the only step whose failure would otherwise
	# leave the owner on cooldown for an ability that never went off.
	if cost_effect != null:
		var charged: ActiveGameplayEffect = owner_asc.apply_gameplay_effect(
			cost_effect, owner_asc, ability_level
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
func abort_ability() -> void:
	if is_active:
		end_ability(true)


## Close the ability. It stays granted: ending is not un-granting.
func end_ability(was_cancelled: bool = false) -> void:
	is_active = false
	# The one place a commit is forgotten. `try_activate` deliberately does not
	# clear it as well: an idle ability holds `_committed == false` as an
	# invariant, and resetting at both ends gives one transition two owners.
	_committed = false
	ability_ended.emit(was_cancelled)
#endregion


#region Commit contract
## Whether `effect` is a legal ability cost. Null is legal: abilities may be free.
##
## A cost must be an instant, purely additive charge that announces nothing. That
## is the only shape `can_afford_cost` can preview honestly and the only one a
## rollback could undo, which is why these are refusals and not warnings.
func _validate_cost_definition(effect: GameplayEffect) -> bool:
	if effect == null:
		return true
	if effect.policy != GameplayEffect.DurationPolicy.INSTANT:
		return false
	# An instant effect grants no tags in any case, so declaring one means the
	# author expected something this cost can never deliver.
	if not effect.granted_tags.is_empty():
		return false
	if not _is_quiet_transaction_effect(effect):
		return false
	return _modifiers_are_a_pure_charge(effect)


## Every modifier subtracts, and at least one of them actually costs something.
##
## Only ADD is allowed. MULTIPLY, DIVIDE and OVERRIDE each depend on the value
## they are charged against, so the amount previewed and the amount taken could
## differ, and the charge could not be undone by adding a fixed amount back.
## A consequence worth naming: this is why a percentage cost cannot be written
## here. It is a different semantics, not a special case of this one.
func _modifiers_are_a_pure_charge(effect: GameplayEffect) -> bool:
	if effect.modifiers.is_empty():
		return false
	var charges_something: bool = false
	for modifier: GameplayEffectModifier in effect.modifiers:
		if modifier == null:
			return false
		if modifier.operation != GameplayEffectModifier.Operation.ADD:
			return false
		var magnitude: float = modifier.calculate_magnitude(ability_level)
		if magnitude > 0.0:
			return false
		if magnitude < 0.0:
			charges_something = true
	return charges_something


## Whether `effect` is a legal cooldown. Null is legal: an ability may have none.
##
## A cooldown is a tag that expires. It moves no attribute, because an attribute
## it had moved would be reverted by the same rollback that retires it.
func _validate_cooldown_definition(effect: GameplayEffect) -> bool:
	if effect == null:
		return true
	if not effect.modifiers.is_empty():
		return false
	# The tag is the cooldown. Without one, nothing can be asked whether the
	# ability is still on cooldown, and the effect expires unobserved.
	if effect.granted_tags.is_empty():
		return false
	if not _is_quiet_transaction_effect(effect):
		return false
	if effect.policy == GameplayEffect.DurationPolicy.DURATION:
		return effect.duration > 0.0
	if effect.policy == GameplayEffect.DurationPolicy.TURN_BASED:
		return effect.duration_turns > 0
	return false


## The conditions a cost and a cooldown share: not periodic, and silent.
##
## Both are transaction bookkeeping rather than gameplay. An execution, a purge,
## a cue or an event would be an observable side effect, and a commit that rolled
## back could not take it back. Written once because the two validators have to
## agree; two copies of the same eight conditions would eventually stop agreeing.
func _is_quiet_transaction_effect(effect: GameplayEffect) -> bool:
	return (
		is_zero_approx(effect.period)
		and effect.executions.is_empty()
		and effect.remove_effects_with_tags.is_empty()
		and effect.application_required_tags.is_empty()
		and effect.application_ignore_tags.is_empty()
		and effect.application_cue_tags.is_empty()
		and effect.periodic_cue_tags.is_empty()
		and effect.event_tags.is_empty()
	)


## Every cooldown this commit must start, once each.
##
## Its own first, then the shared ones in declaration order. A Resource listed in
## both is one cooldown, not two: applying it twice would either refresh it -
## hiding the second application - or stack it, and neither is what sharing a
## cooldown means.
func _unique_cooldown_effects() -> Array[GameplayEffect]:
	var unique: Array[GameplayEffect] = []
	if cooldown_effect != null:
		unique.append(cooldown_effect)
	for shared: GameplayEffect in shared_cooldown_effects:
		if shared != null and not unique.has(shared):
			unique.append(shared)
	return unique
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


## Build a spec from an effect and fire it at every target.
##
## Each target receives its own spec copy, made by
## `apply_effect_spec_to_target`. Sharing one spec across an AoE let target A's
## evaluation change what target B received.
func apply_effect_to_targets(
	effect_res: GameplayEffect, target_data: GameplayAbilityTargetData
) -> void:
	if effect_res == null or target_data == null or owner_asc == null:
		return

	# The instigator and causer are both the persistent avatar. Passing `self`
	# would name a transient node as the cause and leave a dangling reference
	# once the ability ends.
	var avatar: Node = owner_asc.get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(avatar, avatar)
	context.target_data = target_data

	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect_res, context, ability_level)
	for target: Node in target_data.get_target_nodes():
		var target_asc: AbilitySystemComponent = find_asc_on(target)
		if target_asc != null:
			owner_asc.apply_effect_spec_to_target(spec, target_asc)


## The ASC on a node or one of its immediate children.
static func find_asc_on(node: Node) -> AbilitySystemComponent:
	if node == null:
		return null
	var direct: AbilitySystemComponent = node as AbilitySystemComponent
	if direct != null:
		return direct
	for child: Node in node.get_children():
		var child_asc: AbilitySystemComponent = child as AbilitySystemComponent
		if child_asc != null:
			return child_asc
	return null


## Every tag that represents a cooldown for this ability: its own, those of the
## shared cooldown effects, and any declared explicitly.
func get_cooldown_tags() -> Array[StringName]:
	var cooldown_tags: Array[StringName] = []
	if cooldown_effect != null:
		cooldown_tags.append_array(cooldown_effect.granted_tags)
	for effect: GameplayEffect in shared_cooldown_effects:
		if effect != null:
			cooldown_tags.append_array(effect.granted_tags)
	cooldown_tags.append_array(shared_cooldown_tags)
	return cooldown_tags
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
