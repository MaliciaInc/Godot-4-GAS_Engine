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

## Who caused this application. Runtime state, resolved once and carried into
## every application copy - never authoring, never serialized. A SOURCE
## capture reads whichever ASC this names, not whatever Node the evaluator
## happens to be standing on when it asks.
var source_asc: AbilitySystemComponent = null

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

## Every capture this spec's execution calculations declared, keyed by the
## definition Resource itself. Not exposed directly: the public contract is
## register/capture/resolve, so two definitions that happen to describe the
## same attribute stay two separate slots, never accidentally merged.
var _captures: Dictionary[GameplayAttributeCaptureDefinition, GameplayCapturedAttribute] = {}


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
	# Stable across every copy of one spec: who caused it does not change
	# per target. A SOURCE snapshot already taken travels with it too, so a
	# capture common to an AoE reads identically on every target; a TARGET
	# snapshot does not exist yet on a fresh copy and each target takes its
	# own, immediately before that target's own evaluation.
	copy.source_asc = source_asc
	for definition: GameplayAttributeCaptureDefinition in _captures:
		var original: GameplayCapturedAttribute = _captures[definition]
		var captured: GameplayCapturedAttribute = GameplayCapturedAttribute.new()
		captured.definition = definition
		captured.has_snapshot = original.has_snapshot
		captured.snapshot_value = original.snapshot_value
		copy._captures[definition] = captured
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


#region Attribute captures
## Declare that this spec should track `definition`. Idempotent - asking
## twice for the same Resource is one slot, not two - so every execution
## calculation on an effect can register its own captures without needing to
## know what the others already asked for.
func register_capture(definition: GameplayAttributeCaptureDefinition) -> bool:
	if definition == null or definition.attribute_name == &"":
		return false
	if not _captures.has(definition):
		var captured: GameplayCapturedAttribute = GameplayCapturedAttribute.new()
		captured.definition = definition
		_captures[definition] = captured
	return true


## Register every capture this spec's execution calculations declare, and
## take every SOURCE+SNAPSHOT one now. Idempotent throughout: safe to call
## once on a shared spec before it is copied for a target, and again -
## harmlessly - on each copy that already carries an earlier snapshot.
func prepare_captures(resolved_source_asc: AbilitySystemComponent) -> bool:
	if source_asc == null:
		source_asc = resolved_source_asc
	if effect_def != null:
		for execution: GameplayExecutionCalculation in effect_def.executions:
			if execution == null:
				continue
			for definition: GameplayAttributeCaptureDefinition in execution.required_captures():
				register_capture(definition)
	return capture_source_attributes(source_asc)


## Snapshot every registered SOURCE+SNAPSHOT capture from `source_asc`. Called
## once, before this spec is copied for any target - a capture already
## snapshotted is left alone, so a later call on an application copy that
## inherited it cannot overwrite a value the whole AoE is meant to share.
func capture_source_attributes(from_asc: AbilitySystemComponent) -> bool:
	return _capture_all(GameplayAttributeCaptureDefinition.Actor.SOURCE, from_asc)


## Snapshot every registered TARGET+SNAPSHOT capture from `target_asc`. Called
## on this application copy alone, immediately before evaluating it - never
## shared with another target the same spec was also copied for.
func capture_target_attributes(target_asc: AbilitySystemComponent) -> bool:
	return _capture_all(GameplayAttributeCaptureDefinition.Actor.TARGET, target_asc)


func _capture_all(actor: GameplayAttributeCaptureDefinition.Actor, asc: AbilitySystemComponent) -> bool:
	var ok: bool = true
	for definition: GameplayAttributeCaptureDefinition in _captures:
		if definition.actor != actor or definition.policy != GameplayAttributeCaptureDefinition.Policy.SNAPSHOT:
			continue
		var captured: GameplayCapturedAttribute = _captures[definition]
		if captured.has_snapshot:
			continue
		var result: AttributeCaptureResult = _read_attribute(definition, asc)
		if not result.is_ok():
			ok = false
			continue
		captured.has_snapshot = true
		captured.snapshot_value = result.value
	return ok


## Resolve one capture's current value: the frozen SNAPSHOT taken earlier if
## there is one, or a fresh read otherwise - which a LIVE capture always
## needs, and a SNAPSHOT one that was never successfully taken falls back to
## too, so the precise reason (SOURCE_MISSING, ATTRIBUTE_NOT_FOUND, ...) is
## still the one `_capture_all` would have found, not a generic catch-all.
## The asc read for a fresh capture is chosen by the definition's own actor,
## not by which of the two the caller happens to have at hand - a SOURCE
## capture always reads `source_asc`, even from a call that only otherwise
## deals with the target.
func resolve_capture(
	definition: GameplayAttributeCaptureDefinition,
	from_source_asc: AbilitySystemComponent,
	from_target_asc: AbilitySystemComponent
) -> AttributeCaptureResult:
	if definition == null:
		var missing: AttributeCaptureResult = AttributeCaptureResult.new()
		missing.status = AttributeCaptureResult.Status.INVALID_DEFINITION
		return missing

	if definition.policy == GameplayAttributeCaptureDefinition.Policy.SNAPSHOT:
		var captured: GameplayCapturedAttribute = _captures.get(definition)
		if captured != null and captured.has_snapshot:
			var resolved: AttributeCaptureResult = AttributeCaptureResult.new()
			resolved.value = captured.snapshot_value
			return resolved

	var live_asc: AbilitySystemComponent = (
		from_source_asc if definition.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE
		else from_target_asc
	)
	return _read_attribute(definition, live_asc)


func _read_attribute(
	definition: GameplayAttributeCaptureDefinition, asc: AbilitySystemComponent
) -> AttributeCaptureResult:
	var result: AttributeCaptureResult = AttributeCaptureResult.new()
	if definition == null or definition.attribute_name == &"":
		result.status = AttributeCaptureResult.Status.INVALID_DEFINITION
		return result
	if asc == null:
		result.status = (
			AttributeCaptureResult.Status.SOURCE_MISSING
			if definition.actor == GameplayAttributeCaptureDefinition.Actor.SOURCE
			else AttributeCaptureResult.Status.TARGET_MISSING
		)
		return result
	if not asc.has_attribute(definition.attribute_name):
		result.status = AttributeCaptureResult.Status.ATTRIBUTE_NOT_FOUND
		return result

	var value: float = (
		asc.get_attribute_base(definition.attribute_name)
		if definition.value == GameplayAttributeCaptureDefinition.Value.BASE
		else asc.get_attribute_current(definition.attribute_name)
	)
	if not is_finite(value):
		result.status = AttributeCaptureResult.Status.NON_FINITE_VALUE
		return result

	result.value = value
	return result
#endregion
