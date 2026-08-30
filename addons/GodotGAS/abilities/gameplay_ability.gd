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

	var success: bool = await _activate_ability()

	# The subclass may already have ended the ability; only close it if it did
	# not, so `ability_ended` fires exactly once.
	if is_active:
		end_ability(not success)

	current_context = null
	return success


## Pay the cost and start the cooldowns together.
##
## Call this from `_activate_ability` the moment the ability is committed, so a
## cancelled cast has not already charged the player.
func commit_ability() -> void:
	if owner_asc == null:
		return
	if cost_effect != null:
		owner_asc.apply_gameplay_effect(cost_effect, owner_asc, ability_level)
	if cooldown_effect != null:
		owner_asc.apply_gameplay_effect(cooldown_effect, owner_asc, ability_level)
	for shared_effect: GameplayEffect in shared_cooldown_effects:
		if shared_effect != null:
			owner_asc.apply_gameplay_effect(shared_effect, owner_asc, ability_level)


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
