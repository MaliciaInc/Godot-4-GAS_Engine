## One application of a GameplayEffect: the immutable definition plus all the
## runtime state that belongs to this application and no other.
##
## Fixes an upstream defect: runtime magnitudes were keyed by attribute name,
## so `Attack ADD +10` and `Attack MULTIPLY 2` shared one slot and the second
## overwrote the first - the key is now the modifier's index inside
## `effect_def.modifiers`, stable for the spec's life. `create_application_copy()`
## gives each AoE target its own spec, sharing only the immutable definition -
## see that method for what a copy shares and what it does not.
##
## @meta_addon: GAS_Engine
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
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

## The ability or effect level authored magnitudes resolve at.
var level: float = 1.0

## When this application happened, in seconds.
var application_time: float = 0.0

## Tags injected at runtime by an execution calculation or an ability.
var dynamic_tags: Array[StringName] = []

## The source's tags when source_asc was resolved, for
## GameplayEffectQuery.source_tags - "what did the caster have when cast"
## must not drift as the caster changes afterward.
var source_tags_snapshot: Array[StringName] = []

## Runtime duration, mutable by an execution calculation before application.
var duration: float = 0.0

## Runtime turn count, mutable the same way.
var remaining_turns: int = 0

## Runtime period, mutable the same way.
var period: float = 0.0

## Synchronized with the ActiveGameplayEffect stack it joins, if any - always
## 1 outside GameplayEffectStackingRuntime, the only writer.
var stack_count: int = 1

## Overflow_effects hops that produced this application: 0 for a normal cast,
## parent+1 for an overflow child. Refused past
## GameplayEffectRuntime.MAX_EFFECT_CHAIN_DEPTH so a cycle cannot recurse forever.
var chain_depth: int = 0

## Runtime override per modifier index, set by an execution calculation
## during evaluation. Private and generic: the public contract is
## get_magnitude/set_magnitude, so the storage shape can change freely.
## Always wins over authored resolution (`_evaluation_magnitude_cache`
## below) - an override is the runtime overruling the authoring.
var _runtime_magnitude_overrides: Dictionary[int, float] = {}

## Every authored modifier magnitude resolved for the evaluation in progress,
## keyed by modifier index. Rebuilt each evaluation (`_begin_evaluation_cache`)
## so a LIVE magnitude never answers with a stale, previously-resolved value.
var _evaluation_magnitude_cache: Dictionary[int, float] = {}

## Whether an evaluation is currently resolving this spec. Gates reading
## `_evaluation_magnitude_cache`: outside evaluation, a value the last run
## resolved is exactly the staleness `get_magnitude()` must not hand back.
var _evaluation_active: bool = false

## Values the caster supplied at cast time for this spec's
## GameplaySetByCallerMagnitudes, keyed by data tag.
var _set_by_caller: Dictionary[StringName, float] = {}

## Set once evaluation has begun. `set_set_by_caller()` refuses after this -
## it is pre-application input, not something a running evaluation sees change.
var _sealed: bool = false

## Set when anything asked for a modifier index this effect does not have -
## the evaluator turns this into INVALID_MODIFIER_INDEX and fails the whole
## application, rather than letting a typo ship as a silently weaker ability.
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
#endregion


#region Runtime magnitudes
func modifier_count() -> int:
	return effect_def.modifiers.size() if effect_def != null else 0


func _is_valid_index(modifier_index: int) -> bool:
	return modifier_index >= 0 and modifier_index < modifier_count()


## The runtime magnitude of one modifier:
##
##   1. a runtime override, if an execution calculation set one;
##   2. this evaluation's already-resolved authored value, if one is
##      currently being prepared;
##   3. for a GameplayScalableMagnitude, resolved fresh from just the
##      level - it needs no capture or ASC, so asking outside evaluation
##      still answers honestly;
##   4. anything else asked outside evaluation - a capture or SetByCaller
##      magnitude with no evaluation in progress to resolve it against -
##      flags the access and answers 0.0, the same way an out-of-range
##      index always has, rather than inventing a number.
##
## An out-of-range index flags the spec rather than returning a quiet zero, and
## the evaluator refuses the whole application. The policy lives here, not at
## each call site.
func get_magnitude(modifier_index: int) -> float:
	if not _is_valid_index(modifier_index):
		_invalid_magnitude_access = true
		return 0.0
	if _runtime_magnitude_overrides.has(modifier_index):
		return _runtime_magnitude_overrides[modifier_index]
	if _evaluation_active and _evaluation_magnitude_cache.has(modifier_index):
		return _evaluation_magnitude_cache[modifier_index]

	var modifier: GameplayEffectModifier = effect_def.modifiers[modifier_index]
	if modifier != null:
		var scalable: GameplayScalableMagnitude = modifier.magnitude as GameplayScalableMagnitude
		if scalable != null:
			var context: GameplayMagnitudeContext = GameplayMagnitudeContext.new()
			context.spec = self
			context.level = level
			var resolved: GameplayMagnitudeResult = scalable.resolve(context)
			if resolved.is_ok():
				return resolved.value

	_invalid_magnitude_access = true
	return 0.0


func set_magnitude(modifier_index: int, value: float) -> void:
	if not _is_valid_index(modifier_index):
		_invalid_magnitude_access = true
		push_error(
			"GAS_Engine: modifier index " + str(modifier_index)
			+ " is out of range for this effect; the application will be refused."
		)
		return
	_runtime_magnitude_overrides[modifier_index] = value


func had_invalid_magnitude_access() -> bool:
	return _invalid_magnitude_access
#endregion


#region Evaluation cache
## Begin one evaluation. The authored-magnitude cache starts empty, rebuilt
## fresh so a LIVE magnitude never reads an earlier evaluation, and this
## spec seals against further `set_set_by_caller()` calls.
func _begin_evaluation_cache() -> void:
	_evaluation_magnitude_cache.clear()
	_evaluation_active = true
	_sealed = true


func _end_evaluation_cache() -> void:
	_evaluation_active = false


func _cache_evaluation_magnitude(modifier_index: int, value: float) -> void:
	_evaluation_magnitude_cache[modifier_index] = value
#endregion


#region SetByCaller
## Supply a caster value for a GameplaySetByCallerMagnitude tagged `tag`.
## Refused once evaluation has begun, for a bad tag, or a non-finite value.
func set_set_by_caller(tag: StringName, value: float) -> bool:
	if _sealed or tag == &"" or not is_finite(value):
		return false
	_set_by_caller[tag] = value
	return true


func has_set_by_caller(tag: StringName) -> bool:
	return _set_by_caller.has(tag)


func get_set_by_caller(tag: StringName) -> GameplayMagnitudeResult:
	if not _set_by_caller.has(tag):
		return GameplayMagnitudeResult.failure(GameplayMagnitudeResult.Status.MISSING_SET_BY_CALLER)
	return GameplayMagnitudeResult.ok(_set_by_caller[tag])
#endregion


#region Application copy
## A spec for one more target, sharing only what is immutable.
##
## The contract: the definition is shared, the context is a separate
## runtime instance, dynamic tags and magnitudes are duplicated, and anything
## accumulated for the previous target starts clean. Nothing mutable is
## shared, so writing to this copy cannot be observed through the original.
## Null propagates from a context whose own copy failed (an uncopyable
## payload) - apply_effect_spec_result() already refuses a null spec.
func create_application_copy() -> GameplayEffectSpec:
	var context_copy: GameplayEffectContext = context.create_application_copy() if context != null else null
	if context != null and context_copy == null:
		return null

	var copy: GameplayEffectSpec = GameplayEffectSpec.new()
	copy.effect_def = effect_def
	copy.level = level
	copy.application_time = application_time
	copy.duration = duration
	copy.remaining_turns = remaining_turns
	copy.period = period
	copy.chain_depth = chain_depth
	copy.context = context_copy
	copy.dynamic_tags = dynamic_tags.duplicate()
	copy.source_tags_snapshot = source_tags_snapshot.duplicate()
	copy._runtime_magnitude_overrides = _runtime_magnitude_overrides.duplicate()
	# SetByCaller is pre-application input an AoE shares, duplicated so a
	# later set_set_by_caller() on one copy is never observed through
	# another. copy._sealed starts false: each copy seals on its own
	# evaluation, not the moment this one was taken.
	copy._set_by_caller = _set_by_caller.duplicate()
	# Stable per target: a SOURCE snapshot travels with it so an AoE capture
	# reads identically everywhere; a TARGET snapshot does not exist yet and
	# each target takes its own before its own evaluation.
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


## Whether the spec carries a tag: granted, static asset, or dynamic asset.
## New code should ask the specific getter instead - get_granted_tags() or
## get_asset_tags() - this is an ambiguous union kept for old F2 call sites.
func has_tag(tag: StringName) -> bool:
	return get_granted_tags().has(tag) or get_asset_tags().has(tag)


## Inject a tag, for an execution calculation marking a hit as Critical, Dodged
## and so on. Documented as a dynamic ASSET tag: it describes this
## application, the same as a static GameplayEffectAssetTagsComponent entry,
## so SetByCaller/event injections do not create a third, ownerless category.
func inject_tag(tag: StringName) -> void:
	if not dynamic_tags.has(tag):
		dynamic_tags.append(tag)


## Every asset tag this application carries: the effect's own static asset
## tags plus whatever was injected at runtime.
func get_asset_tags() -> Array[StringName]:
	var tags: Array[StringName] = effect_def.get_asset_tags() if effect_def != null else []
	tags.append_array(dynamic_tags)
	return tags


## Every tag this application grants to its target.
func get_granted_tags() -> Array[StringName]:
	return effect_def.get_granted_tags() if effect_def != null else []
#endregion


#region Component states
## Prepared component state for the application currently in flight, indexed
## the same as effect_def.components. Temporary: GameplayEffectRuntime clears
## it once the application commits (states moved to the ActiveGameplayEffect)
## or is refused (each component already told to discard_prepared()).
var _prepared_component_states: Array[GameplayEffectComponentState] = []

func set_prepared_component_states(states: Array[GameplayEffectComponentState]) -> void:
	_prepared_component_states = states

func prepared_component_states() -> Array[GameplayEffectComponentState]:
	return _prepared_component_states
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


## Register every capture this spec's execution calculations AND modifier
## magnitudes declare, and take every SOURCE+SNAPSHOT one now. Idempotent
## throughout: safe to call once on a shared spec before it is copied for a
## target, and again - harmlessly - on each copy that already carries an
## earlier snapshot.
func prepare_captures(resolved_source_asc: AbilitySystemComponent) -> bool:
	if source_asc == null:
		source_asc = resolved_source_asc
		if source_asc != null:
			source_tags_snapshot = source_asc.tags.active_tags()
	if effect_def != null:
		for execution: GameplayExecutionCalculation in effect_def.executions:
			if execution == null:
				continue
			for definition: GameplayAttributeCaptureDefinition in execution.required_captures():
				register_capture(definition)
		for modifier: GameplayEffectModifier in effect_def.modifiers:
			if modifier == null or modifier.magnitude == null:
				continue
			for definition: GameplayAttributeCaptureDefinition in modifier.magnitude.required_captures():
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
