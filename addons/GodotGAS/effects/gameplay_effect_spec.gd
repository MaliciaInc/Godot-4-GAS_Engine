## One application of a GameplayEffect: the immutable definition plus all the
## runtime state that belongs to this application and no other.
##
## Two upstream defects are fixed here.
##
## **Runtime magnitudes were keyed by attribute name.** An effect with
## `Attack ADD +10` and `Attack MULTIPLY 2` had one slot for both, so the second
## modifier overwrote the first and the effect silently did half its job. The
## key is the modifier's index inside `effect_def.modifiers`, which is stable
## for the life of the spec and distinguishes two modifiers that write the same
## attribute.
##
## **One spec was handed to several targets.** A spec is RefCounted and holds
## mutable state, so an AoE let target A's evaluation change what target B
## received. `create_application_copy()` gives each target its own, sharing only
## the immutable definition.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayEffectSpec extends RefCounted

## The immutable definition. Shared between copies on purpose: it is a designer
## asset and nothing may write to it at runtime.
var effect_def: GameplayEffect = null

## The runtime context. Never shared between applications - it is mutable.
var context: GameplayEffectContext = null

## The ability or effect level these magnitudes were snapshotted at.
var level: float = 1.0

## When this application happened, in seconds.
var application_time: float = 0.0

## Tags injected at runtime by an execution calculation or an ability.
var dynamic_tags: Array[StringName] = []

## Runtime duration, mutable by an execution calculation before application.
var duration: float = 0.0

## Runtime turn count, mutable the same way.
var remaining_turns: int = 0

## Runtime period, mutable the same way.
var period: float = 0.0

## Runtime magnitude per modifier index. Private and generic on purpose: the
## public contract is get_magnitude/set_magnitude, so the storage shape can
## change without every execution calculation in the game changing with it.
var _magnitudes: Dictionary[int, float] = {}

## Set when anything asked for a modifier index this effect does not have.
## The evaluator turns this into INVALID_MODIFIER_INDEX and fails the whole
## application. Returning 0.0 and carrying on would let a typo in an execution
## calculation ship as a silently weaker ability.
var _invalid_magnitude_access: bool = false


#region Initialization
func _init(
	in_effect: GameplayEffect = null, in_context: GameplayEffectContext = null, in_level: float = 1.0
) -> void:
	effect_def = in_effect
	context = in_context
	level = in_level
	application_time = Time.get_ticks_msec() / 1000.0
	if in_effect == null:
		return

	duration = in_effect.duration
	period = in_effect.period
	remaining_turns = in_effect.duration_turns
	_snapshot_magnitudes()


## Snapshot every modifier's magnitude at this level, by index.
##
## Standard magnitudes are snapshotted per application. A later
## change to the source's stats does not retroactively alter an active buff.
func _snapshot_magnitudes() -> void:
	for index: int in effect_def.modifiers.size():
		var modifier: GameplayEffectModifier = effect_def.modifiers[index]
		if modifier == null:
			continue
		_magnitudes[index] = modifier.calculate_magnitude(level)
#endregion


#region Runtime magnitudes
func modifier_count() -> int:
	return effect_def.modifiers.size() if effect_def != null else 0


func _is_valid_index(modifier_index: int) -> bool:
	return modifier_index >= 0 and modifier_index < modifier_count()


## The runtime magnitude of one modifier.
##
## An out-of-range index flags the spec rather than returning a quiet zero, and
## the evaluator refuses the whole application. The policy lives here, not at
## each call site.
func get_magnitude(modifier_index: int) -> float:
	if not _is_valid_index(modifier_index):
		_invalid_magnitude_access = true
		return 0.0
	return _magnitudes.get(modifier_index, 0.0)


func set_magnitude(modifier_index: int, value: float) -> void:
	if not _is_valid_index(modifier_index):
		_invalid_magnitude_access = true
		push_error(
			"GodotGAS: modifier index " + str(modifier_index)
			+ " is out of range for this effect; the application will be refused."
		)
		return
	_magnitudes[modifier_index] = value


func had_invalid_magnitude_access() -> bool:
	return _invalid_magnitude_access
#endregion


#region Application copy
## A spec for one more target, sharing only what is immutable.
##
## The contract: the definition is shared, the context is a separate
## runtime instance, dynamic tags and magnitudes are duplicated, and anything
## accumulated for the previous target starts clean. Nothing mutable is shared,
## so writing to this copy cannot be observed through the original.
func create_application_copy() -> GameplayEffectSpec:
	var copy: GameplayEffectSpec = GameplayEffectSpec.new()
	copy.effect_def = effect_def
	copy.level = level
	copy.application_time = application_time
	copy.duration = duration
	copy.remaining_turns = remaining_turns
	copy.period = period
	copy.context = context.create_application_copy() if context != null else null
	copy.dynamic_tags = dynamic_tags.duplicate()
	copy._magnitudes = _magnitudes.duplicate()
	# Deliberately NOT copied: the invalid-access flag belongs to the evaluation
	# that raised it, not to a fresh application of the same effect.
	return copy
#endregion


#region Context Helpers
func get_target_nodes() -> Array[Node]:
	if context == null:
		return []
	return context.get_target_nodes()


## Whether the spec carries a tag, natively or injected at runtime.
func has_tag(tag: StringName) -> bool:
	if effect_def != null and effect_def.granted_tags.has(tag):
		return true
	return dynamic_tags.has(tag)


## Inject a tag, for an execution calculation marking a hit as Critical, Dodged
## and so on.
func inject_tag(tag: StringName) -> void:
	if not dynamic_tags.has(tag):
		dynamic_tags.append(tag)
#endregion
