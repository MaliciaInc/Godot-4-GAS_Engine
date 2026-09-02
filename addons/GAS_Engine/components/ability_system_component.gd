## The entity's ability system: a facade over five runtimes.
##
## This node owns the signals, the exported configuration and the public API.
## It owns no gameplay state: tags live in GameplayTagRuntime, attributes in
## GameplayAttributeRuntime, effects in GameplayEffectRuntime, timing in
## GameplayEffectScheduler, abilities in AbilityRuntime - one owner per piece
## of mutable state, never a second copy to keep in step. Networking is gone:
## no `@rpc`, `MultiplayerSynchronizer` or authority branch remains.
##
## @meta_addon: GAS_Engine
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name AbilitySystemComponent extends Node

#region Signals
## A tag's count went from zero to one.
signal tag_added(tag: StringName)

## A tag's count changed while staying above zero.
signal tag_count_changed(tag: StringName, new_count: int)

## A tag's count reached zero and it was dropped.
signal tag_removed(tag: StringName)

## An attribute's effective value actually moved. Never emitted for a write that
## resolved to the same value.
signal attribute_changed(
	attribute_name: StringName, old_value: float, new_value: float, effect_spec: GameplayEffectSpec
)

## This ASC successfully applied an effect to someone else.
signal effect_applied_to_target(target_asc: AbilitySystemComponent, spec: GameplayEffectSpec)

## This ASC received an effect from someone.
signal effect_received(source_asc: AbilitySystemComponent, spec: GameplayEffectSpec)

## An application was refused, with the reason and attribute if any. Kept for
## evaluator failures - a component's own reason lives on the finished signal below.
signal effect_application_refused(
	status: AttributeEvaluationResult.Status, attribute_name: StringName
)

## Every apply_*_result() call emits this once, success or failure - every
## reason a legacy refusal signal could carry, plus every component reason.
signal gameplay_effect_application_finished(result: GameplayEffectApplicationResult)

## One periodic tick ran - the same "execution" GameplayEffectComponent.
## on_effect_executed() means, extended to the ASC as one typed signal.
signal gameplay_effect_executed(spec: GameplayEffectSpec, active_effect: ActiveGameplayEffect)

## A gameplay event reached this ASC.
signal gameplay_event_received(event: GameplayEventData)

signal active_effect_added(active_effect: ActiveGameplayEffect)
signal active_effect_removed(active_effect: ActiveGameplayEffect)

## A REFRESH_DURATION reapplication renewed an existing instance - never a
## remove/add pair, or a UI would rebuild an icon that was still there.
signal active_effect_refreshed(active_effect: ActiveGameplayEffect)

## An activation attempt was refused, with the closed reason why.
signal ability_activation_failed(ability: GameplayAbility, reason: AbilityRuntime.ActivationError)

## AbilityRuntime.try_activate() started this instance - accepted, not
## finished. See ability_runtime_ended for the outcome.
signal ability_activated(handle: GameplayAbilityHandle, instance: GameplayAbility)

## The canonical, handle-addressed superset of the instance's own
## `ability_ended` - fires for every activation this ASC started.
signal ability_runtime_ended(
	handle: GameplayAbilityHandle,
	instance: GameplayAbility,
	was_cancelled: bool,
	reason: GameplayAbilityTask.CancelReason
)

## An indirect LIVE-magnitude cycle did not converge within the cap - the
## attribute named is where it was cut off, keeping its last resolved magnitude.
signal live_magnitude_cycle_aborted(attribute_name: StringName)

## An ongoing tag requirement stopped/started being satisfied - never on the
## initial application, never paired with added/removed.
signal active_effect_inhibition_changed(handle: GameplayEffectHandle, inhibited: bool)

## An ongoing/removal reevaluation did not converge within the pass cap.
## Left inhibited as a fail-safe, never removed or left undetermined.
signal effect_requirement_cycle_aborted(handle: GameplayEffectHandle)

## A stack's count actually changed - never for a non-growing overflow, nor
## an expiration policy re-set at the same count.
signal active_effect_stack_changed(handle: GameplayEffectHandle, old_count: int, new_count: int)

## A stack was already at its limit when another application arrived.
signal active_effect_stack_overflowed(handle: GameplayEffectHandle)

## Every removal, typed - superset of `active_effect_removed` (still emitted
## too), which cannot tell expiration apart from remove/cleanse/teardown.
signal gameplay_effect_removal_finished(active_effect: ActiveGameplayEffect, reason: ActiveGameplayEffect.RemovalReason)
#endregion


#region Configuration
@export_category("State Management")
@export var attribute_sets: Array[AttributeSet] = []:
	set(value):
		attribute_sets = value
		if is_node_ready():
			_adopt_attribute_sets()

## When false - Unreal's default - this component works on its own deep copies
## rather than on the authored resources. See `set_attribute_sets()` for what
## sharing them actually costs.
@export var share_attributes: bool = false:
	set(value):
		share_attributes = value
		if is_node_ready():
			_adopt_attribute_sets()
#endregion


# The autoload's script declares no class_name (the singleton owns that
# global name already), so this alias is the type.
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

var attributes: GameplayAttributeRuntime = GameplayAttributeRuntime.new()
var tags: GameplayTagRuntime = GameplayTagRuntime.new()
var effects: GameplayEffectRuntime = GameplayEffectRuntime.new()
var scheduler: GameplayEffectScheduler = GameplayEffectScheduler.new()
var ability_runtime: AbilityRuntime = AbilityRuntime.new()
var events: GameplayEventRuntime = GameplayEventRuntime.new()

#region Lifecycle
func _ready() -> void:
	_wire_runtimes()
	_adopt_attribute_sets()


## The single handover: both exports above route here, so the sets and the
## policy that copies them can never be applied one without the other.
func _adopt_attribute_sets() -> void:
	attributes.set_attribute_sets(attribute_sets, not share_attributes)


func _wire_runtimes() -> void:
	attributes.owner_node = self

	effects.owner_asc = self
	effects.attributes = attributes
	effects.tags = tags
	effects.live_magnitudes.owner_asc = self
	effects.live_magnitudes.effects = effects
	effects.handles.owner_asc = self
	effects.handles.runtime = effects
	effects.inhibition.effects = effects
	effects.stacking.effects = effects
	effects.chain.effects = effects

	scheduler.effects = effects

	ability_runtime.owner_asc = self
	ability_runtime.tags = tags
	ability_runtime.tasks.owner_asc = self
	ability_runtime.instancing.owner_asc = self
	ability_runtime.instancing.ability_runtime = ability_runtime
	ability_runtime.tag_semantics.owner_asc = self
	ability_runtime.tag_semantics.ability_runtime = ability_runtime
	ability_runtime.policies.ability_runtime = ability_runtime
	ability_runtime.lifecycle.ability_runtime = ability_runtime
	ability_runtime.cooldowns.ability_runtime = ability_runtime

	events.owner_asc = self
	events.ability_runtime = ability_runtime


func _process(delta: float) -> void:
	scheduler.advance_time(delta)
	ability_runtime.advance_time(delta)


## Advance turn-based effects. Called by an external turn manager; the frame
## loop never consumes turns.
func advance_turn(turns: int = 1) -> void:
	scheduler.advance_turn(turns)


## Stop everything and return to a clean state.
##
## Idempotent because each of its four steps is: `effects.cleanup()` returns at
## once on an empty registry, `abort_all` walks no specs and asks for no
## reevaluation under ASC_CLEANUP, and the three `clear()`s announce nothing.
## It used to be told so instead, by a flag lowered only when an effect was
## applied - so an ASC cleaned up once and then given an ability had a flag
## saying clean and no effects to contradict it, and the second cleanup returned
## before aborting anything. Cleanup owns four things; the shortcut asked one.
func cleanup() -> void:
	ability_runtime.abort_all(GameplayAbilityTask.CancelReason.ASC_CLEANUP)
	effects.cleanup()
	ability_runtime.clear()
	tags.clear_all()
	attributes.clear_contributions()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		cleanup()
#endregion


#region Runtime callbacks
## Emit the right tag signal for what the tag runtime reported.
func emit_tag_change(tag: StringName, change: GameplayTagRuntime.Change, new_count: int) -> void:
	match change:
		GameplayTagRuntime.Change.ADDED:
			tag_added.emit(tag)
			tag_count_changed.emit(tag, new_count)
		GameplayTagRuntime.Change.INCREMENTED, GameplayTagRuntime.Change.DECREMENTED:
			tag_count_changed.emit(tag, new_count)
		GameplayTagRuntime.Change.REMOVED:
			tag_removed.emit(tag)
		_:
			pass
	effects.on_owner_tags_changed()
	ability_runtime.request_passive_reevaluation()


## Emit an attribute change and run the set's dependency hook, in that order.
func emit_attribute_changed(
	mutation: AttributeMutationResult, source_spec: GameplayEffectSpec
) -> void:
	attribute_changed.emit(
		mutation.attribute_name,
		mutation.old_current_value,
		mutation.new_current_value,
		source_spec
	)
	attributes.notify_current_changed(
		mutation.attribute_name, mutation.old_current_value, mutation.new_current_value
	)
	ability_runtime.request_passive_reevaluation()


## The node cues and effects act on: the entity, not this component.
func get_effect_target() -> Node:
	var parent: Node = get_parent()
	return parent if parent != null else self


## The ASC of whoever caused a spec, when there is one. Asked of the locator
## rather than looked up by name here - a second, weaker answer (a direct
## child by convention, never checked, never climbing a collider to its
## actor) to a question that already had one.
func find_source_asc(spec: GameplayEffectSpec) -> AbilitySystemComponent:
	if spec == null or spec.context == null:
		return null
	return AbilitySystemLocator.find_for_node(spec.context.instigator)


## Broadcast an effect's static and injected event tags.
func dispatch_effect_events(spec: GameplayEffectSpec) -> void:
	for event_tag: StringName in spec.effect_def.event_tags:
		send_gameplay_event(GameplayEventRuntime.from_spec(event_tag, spec, get_effect_target()))
	for dynamic_tag: StringName in spec.dynamic_tags:
		send_gameplay_event(GameplayEventRuntime.from_spec(dynamic_tag, spec, get_effect_target()))
#endregion


#region Cues
## The autoload declares no class_name, so it is typed through its script - a
## bare Node here would make every call to it an unsafe method access. Null,
## never an engine error, when this ASC is mid-teardown and already outside
## the tree - a persistent cue's own removal can reach this from `cleanup()`,
## unlike a one-shot's `execute_cue()`, which never ran there before.
func _cue_manager() -> CueManagerScript:
	if not is_inside_tree():
		return null
	return get_node_or_null(CueManagerScript.AUTOLOAD_NODE_PATH) as CueManagerScript


## Play a one-shot cue on this entity through the global manager.
func execute_cue(params: GameplayCueParams) -> void:
	if params == null:
		return
	if params.target == null:
		params.target = get_effect_target()
	var manager: CueManagerScript = _cue_manager()
	if manager != null:
		manager.execute_cue(params)


## Start a PERSISTENT cue's on_active/while_active. An invalid handle if
## there is no manager or no registry entry for the tag.
func activate_persistent_cue(params: GameplayCueParams) -> GameplayCueHandle:
	if params == null:
		return GameplayCueHandle.new()
	if params.target == null:
		params.target = get_effect_target()
	var manager: CueManagerScript = _cue_manager()
	return manager.activate_persistent_cue(params) if manager != null else GameplayCueHandle.new()


## End and pool a PERSISTENT cue started by `activate_persistent_cue`.
func deactivate_persistent_cue(handle: GameplayCueHandle, params: GameplayCueParams) -> void:
	var manager: CueManagerScript = _cue_manager()
	if manager != null:
		manager.deactivate_persistent_cue(handle, params)
#endregion


#region Attributes
func get_attribute(attribute_name: StringName) -> AttributeData:
	return attributes.find(attribute_name)


func has_attribute(attribute_name: StringName) -> bool:
	return attributes.has(attribute_name)


func get_attribute_base(attribute_name: StringName) -> float:
	return attributes.get_base_value(attribute_name)


func get_attribute_current(attribute_name: StringName) -> float:
	return attributes.get_current_value(attribute_name)


## The one durable-mutation path. No gameplay code writes `current_value`.
func set_attribute_base(
	attribute_name: StringName, new_base_value: float, source_spec: GameplayEffectSpec = null
) -> AttributeMutationResult:
	var staged: AttributeBaseMutation = attributes.stage_base_write(attribute_name, new_base_value)
	if staged == null:
		var missing: AttributeMutationResult = AttributeMutationResult.new()
		missing.status = AttributeEvaluationResult.Status.ATTRIBUTE_NOT_FOUND
		return missing

	var result: AttributeMutationResult = attributes.commit_base_write(staged)
	if result.is_ok():
		effects.recompose_and_emit(source_spec)
	return result


func apply_attribute_base_delta(
	attribute_name: StringName, amount: float, source_spec: GameplayEffectSpec = null
) -> AttributeMutationResult:
	var requested: float = attributes.get_base_value(attribute_name) + amount
	return set_attribute_base(attribute_name, requested, source_spec)


## Replace base values while preserving active contributions - always
## "replace the base", never "reset the entity". A x2 buff over base 10
## shows 20; initializing the base to 50 shows 100, not 80 and not 50,
## because the buff was never touched.
func initialize_attribute_overrides(overrides: Dictionary[StringName, float]) -> void:
	for attribute_name: StringName in overrides:
		set_attribute_base(attribute_name, overrides[attribute_name])
#endregion


#region Effects
## The one entry point every application reaches, self-application included.
## `self` is always the target, so an unresolved SOURCE gets one last chance
## - `context.instigator` - before a required capture refuses.
func apply_effect_spec_result(spec: GameplayEffectSpec) -> GameplayEffectApplicationResult:
	var result: GameplayEffectApplicationResult
	if spec == null:
		result = GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.INVALID_SPEC, spec)
	elif not spec.prepare_captures(find_source_asc(spec)):
		result = GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.EVALUATION_FAILED, spec)
	else:
		result = effects.apply(spec)
	gameplay_effect_application_finished.emit(result)
	return result

## F2 wrapper: the active effect a successful application produced, or null.
func apply_effect_spec(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	return apply_effect_spec_result(spec).active_effect

## Apply an effect to another ASC, giving that target its own spec copy.
## Captures are prepared here, on the shared spec, before it is copied - taken
## later, inside the copy's own apply, a SOURCE+SNAPSHOT would be one target's
## read, not the shared one every target needs.
func apply_effect_spec_to_target_result(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayEffectApplicationResult:
	if target_asc == null or spec == null:
		return GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.INVALID_SPEC, spec)
	if not spec.prepare_captures(self):
		return GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.EVALUATION_FAILED, spec)
	var result: GameplayEffectApplicationResult = target_asc.apply_effect_spec_result(
		spec.create_application_copy()
	)
	if result.is_ok():
		effect_applied_to_target.emit(target_asc, spec)
	return result

func apply_effect_spec_to_target(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> ActiveGameplayEffect:
	return apply_effect_spec_to_target_result(spec, target_asc).active_effect

func apply_gameplay_effect_result(
	effect: GameplayEffect, source_asc: AbilitySystemComponent = null, effect_level: float = 1.0
) -> GameplayEffectApplicationResult:
	if effect == null:
		return GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.INVALID_DEFINITION, null)
	var instigator: Node = source_asc.get_effect_target() if source_asc != null else get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(instigator)
	var spec: GameplayEffectSpec = GameplayEffectSpec.new(effect, context, effect_level)
	spec.source_asc = source_asc
	return apply_effect_spec_result(spec)

func apply_gameplay_effect(
	effect: GameplayEffect, source_asc: AbilitySystemComponent = null, effect_level: float = 1.0
) -> ActiveGameplayEffect:
	return apply_gameplay_effect_result(effect, source_asc, effect_level).active_effect


func remove_active_effect(active_effect: ActiveGameplayEffect) -> void:
	effects.remove(active_effect)

func get_active_effect(handle: GameplayEffectHandle) -> ActiveGameplayEffect:
	return effects.handles.resolve(handle)

func find_active_effects(query: GameplayEffectQuery) -> Array[ActiveGameplayEffect]:
	return effects.handles.find(query)

func find_active_effect_handles(query: GameplayEffectQuery) -> Array[GameplayEffectHandle]:
	return effects.handles.find_handles(query)

func count_active_effects(query: GameplayEffectQuery) -> int:
	return effects.handles.count(query)

func remove_active_effects(query: GameplayEffectQuery) -> int:
	return effects.handles.remove_matching(query)

func remove_active_effect_by_handle(handle: GameplayEffectHandle) -> bool:
	return effects.handles.remove_by_handle(handle)

func get_effect_duration_remaining(handle: GameplayEffectHandle) -> float:
	return effects.handles.duration_remaining(handle)

func get_effect_turns_remaining(handle: GameplayEffectHandle) -> int:
	return effects.handles.turns_remaining(handle)

func remove_effects_with_tag(tag: StringName) -> void:
	effects.remove_effects_with_tag(tag)

func remove_effects_from_source(source_node: Node) -> void:
	effects.remove_effects_from_source(source_node)

func get_active_effects() -> Array[ActiveGameplayEffect]:
	return effects.active_effects()


## Whether every attribute this cost touches can pay it in full from its
## durable base. `GameplayEffectEvaluator.can_afford()` carries the why, and
## runs the very request a commit runs, so a preview cannot disagree with it.
func can_afford_cost(effect: GameplayEffect, effect_level: float = 1.0) -> bool:
	return GameplayEffectEvaluator.can_afford(effect, effect_level, self)
#endregion


#region Tags
func add_tag(tag: StringName) -> void:
	emit_tag_change(tag, tags.add(tag), tags.count(tag))


func remove_tag(tag: StringName) -> void:
	emit_tag_change(tag, tags.remove(tag), tags.count(tag))


func clear_tag(tag: StringName) -> void:
	emit_tag_change(tag, tags.clear(tag), 0)


func has_tag_exact(tag: StringName) -> bool:
	return tags.has_exact(tag)


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func has_any_tags(query: Array[StringName]) -> bool:
	return tags.has_any(query)


func has_all_tags(query: Array[StringName]) -> bool:
	return tags.has_all(query)


## Seconds left on a tag, or INF when something grants it with no end.
func get_tag_duration_remaining(tag: StringName) -> float:
	return effects.tag_duration_remaining(tag)


## Turns left on a tag. Seconds and turns are different units and get different
## questions, so a UI cannot count a turn-based debuff down in seconds.
func get_tag_turns_remaining(tag: StringName) -> int:
	return effects.tag_turns_remaining(tag)
#endregion


#region Abilities, input and events
## Grant an ability from its scene - the one way an ability is ever granted.
## prepare -> commit under the hood; a failed prepare frees whatever it
## instantiated rather than leaving a Node nobody owns.
func give_ability(
	ability_scene: PackedScene,
	level: float = 1.0,
	input_id: int = -1,
	source: GameplayAbilitySource = null
) -> GameplayAbilityHandle:
	return ability_runtime.give_ability(ability_scene, level, input_id, source)


## Convenience for a caller holding the running instance rather than its
## handle. A caller that only has the handle - GLoot's receipt, mainly -
## uses ability_runtime.remove_ability(handle) directly; get_ability_spec
## and get_ability_cooldown_state live there too, for the same reason.
func remove_ability(ability: GameplayAbility) -> void:
	ability_runtime.remove(ability)


func can_activate_ability(ability: GameplayAbility, emit_failure: bool = false) -> bool:
	if ability == null or ability.current_spec == null:
		return false
	var reason: AbilityRuntime.ActivationError = ability_runtime.activation_error(
		ability.current_spec
	)
	if reason == AbilityRuntime.ActivationError.NONE:
		return true
	if emit_failure:
		ability_activation_failed.emit(ability, reason)
	return false


func cancel_abilities_with_tags(cancel_tags: Array[StringName]) -> void:
	ability_runtime.cancel_with_tags(cancel_tags)


## Route an input slot to a granted ability. False when it was never granted.
##
## The runtime refuses and says so; the facade used to drop the answer, so a
## caller binding an ungranted ability found out only when the press reached no one.
func bind_ability_to_input(
	ability: GameplayAbility, input_id: int, unbind_others: bool = true
) -> bool:
	return ability_runtime.bind_to_input(ability, input_id, unbind_others)


func ability_local_input_pressed(input_id: int) -> void:
	ability_runtime.input_pressed(input_id)


func ability_local_input_released(input_id: int) -> void:
	ability_runtime.input_released(input_id)


func register_ability_task(task: GameplayAbilityTask) -> GameplayAbilityTask:
	return ability_runtime.register_task(task)


func cancel_ability_tasks(ability: GameplayAbility, reason: GameplayAbilityTask.CancelReason) -> void:
	ability_runtime.cancel_tasks_for_ability(ability, reason)


func submit_ability_target_data(ability: GameplayAbility, data: GameplayAbilityTargetData) -> void:
	ability_runtime.submit_target_data(ability, data)


func send_gameplay_event(event: GameplayEventData) -> void:
	# A task already waiting for this event hears it before it can wake a
	# sleeping ability that would then wait for the same one.
	ability_runtime.tasks.gameplay_event(event)
	events.dispatch(event, ability_runtime.specs())
#endregion
