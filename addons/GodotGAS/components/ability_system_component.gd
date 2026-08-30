## The entity's ability system: a facade over five runtimes.
##
## This node owns the signals, the exported configuration and the public API.
## It owns no gameplay state: tags live in GameplayTagRuntime, attributes in
## GameplayAttributeRuntime, effects in GameplayEffectRuntime, timing in
## GameplayEffectScheduler, abilities in AbilityRuntime. Each piece of mutable
## state has exactly one owner, so there is never a second copy to keep in step.
##
## Networking is gone. The behaviour of this addon is local,
## and no `@rpc`, `MultiplayerSynchronizer` or authority branch remains.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
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

## An application was refused. Carries the typed reason and, when the reason
## names one, the attribute it was about.
signal effect_application_refused(
	status: AttributeEvaluationResult.Status, attribute_name: StringName
)

## A gameplay event reached this ASC.
signal gameplay_event_received(event: GameplayEventData)

signal active_effect_added(active_effect: ActiveGameplayEffect)
signal active_effect_removed(active_effect: ActiveGameplayEffect)

## A REFRESH_DURATION reapplication renewed an existing instance. Emitted
## instead of a remove/add pair, because the logical instance never went away
## and a UI that saw the pair would rebuild an icon that was still there.
signal active_effect_refreshed(active_effect: ActiveGameplayEffect)

## An activation attempt was refused, with the closed reason why.
signal ability_activation_failed(ability: GameplayAbility, reason: AbilityRuntime.ActivationError)
#endregion


#region Configuration
@export_category("State Management")
@export var attribute_sets: Array[AttributeSet] = []

## When false, this ASC deep-copies its attribute sets on ready so two entities
## sharing a Resource do not share their stats. Matches Unreal's default.
@export var share_attributes: bool = false
#endregion


# The cue manager is an autoload, so its script cannot also declare a
# class_name: the singleton already owns that global name. The type still
# has to come from somewhere, so this one alias stays.
const CueManagerScript = preload("res://addons/GodotGAS/managers/gameplay_cue_manager.gd")

var attributes: GameplayAttributeRuntime = GameplayAttributeRuntime.new()
var tags: GameplayTagRuntime = GameplayTagRuntime.new()
var effects: GameplayEffectRuntime = GameplayEffectRuntime.new()
var scheduler: GameplayEffectScheduler = GameplayEffectScheduler.new()
var ability_runtime: AbilityRuntime = AbilityRuntime.new()
var events: GameplayEventRuntime = GameplayEventRuntime.new()

var _cleaned_up: bool = false


#region Lifecycle
func _ready() -> void:
	_isolate_attribute_sets()
	_wire_runtimes()
	attributes.initialize()


## Give this entity its own copy of each set unless sharing was asked for.
## Without this, two enemies built from one Resource share one health pool.
func _isolate_attribute_sets() -> void:
	if share_attributes:
		return
	for index: int in attribute_sets.size():
		if attribute_sets[index] != null:
			attribute_sets[index] = attribute_sets[index].duplicate(true)


func _wire_runtimes() -> void:
	attributes.owner_node = self
	attributes.set_attribute_sets(attribute_sets)

	effects.owner_asc = self
	effects.attributes = attributes
	effects.tags = tags

	scheduler.effects = effects

	ability_runtime.owner_asc = self
	ability_runtime.tags = tags
	ability_runtime.tasks.owner_asc = self

	events.owner_asc = self


func _process(delta: float) -> void:
	scheduler.advance_time(delta)
	ability_runtime.advance_time(delta)


## Advance turn-based effects. Called by an external turn manager; the frame
## loop never consumes turns.
func advance_turn(turns: int = 1) -> void:
	scheduler.advance_turn(turns)


## Stop everything and return to a clean state. Idempotent: calling it twice
## emits nothing the second time.
func cleanup() -> void:
	if _cleaned_up and effects.active_count() == 0:
		return
	ability_runtime.abort_all(GameplayAbilityTask.CancelReason.ASC_CLEANUP)
	effects.cleanup()
	ability_runtime.clear()
	tags.clear_all()
	attributes.clear_contributions()
	_cleaned_up = true


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


## The node cues and effects act on: the entity, not this component.
func get_effect_target() -> Node:
	var parent: Node = get_parent()
	return parent if parent != null else self


## The ASC of whoever caused a spec, when there is one.
func find_source_asc(spec: GameplayEffectSpec) -> AbilitySystemComponent:
	if spec == null or spec.context == null or spec.context.instigator == null:
		return null
	return spec.context.instigator.get_node_or_null("AbilitySystemComponent")


## Broadcast an effect's static and injected event tags.
func dispatch_effect_events(spec: GameplayEffectSpec) -> void:
	for event_tag: StringName in spec.effect_def.event_tags:
		send_gameplay_event(GameplayEventRuntime.from_spec(event_tag, spec, get_effect_target()))
	for dynamic_tag: StringName in spec.dynamic_tags:
		send_gameplay_event(GameplayEventRuntime.from_spec(dynamic_tag, spec, get_effect_target()))
#endregion


#region Cues
## Play a cue on this entity through the global manager.
func execute_cue(params: GameplayCueParams) -> void:
	if params == null:
		return
	if params.target == null:
		params.target = get_effect_target()
	# The autoload declares no class_name, so it is typed through its script.
	# A bare Node here would make every call to it an unsafe method access.
	var manager: CueManagerScript = get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	if manager == null:
		return
	manager.execute_cue(params)
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


## Replace base values while preserving active contributions.
##
## This always means "replace the base", never "reset the entity".
## A x2 buff over base 10 shows 20; initializing the base to 50 shows 100, not
## 80 and not 50, because the buff was never touched.
func initialize_attribute_overrides(overrides: Dictionary[StringName, float]) -> void:
	for attribute_name: StringName in overrides:
		set_attribute_base(attribute_name, overrides[attribute_name])
#endregion


#region Effects
func apply_effect_spec(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	_cleaned_up = false
	return effects.apply(spec)


## Apply an effect to another ASC, giving that target its own spec copy.
func apply_effect_spec_to_target(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> ActiveGameplayEffect:
	if target_asc == null or spec == null:
		return null
	var applied: ActiveGameplayEffect = target_asc.apply_effect_spec(spec.create_application_copy())
	if applied != null:
		effect_applied_to_target.emit(target_asc, spec)
	return applied


## Wrap a raw effect into a spec and apply it here.
func apply_gameplay_effect(
	effect: GameplayEffect, source_asc: AbilitySystemComponent = null, effect_level: float = 1.0
) -> ActiveGameplayEffect:
	if effect == null:
		return null
	var instigator: Node = source_asc.get_effect_target() if source_asc != null else get_effect_target()
	var context: GameplayEffectContext = GameplayEffectContext.new(instigator)
	return apply_effect_spec(GameplayEffectSpec.new(effect, context, effect_level))


func remove_active_effect(active_effect: ActiveGameplayEffect) -> void:
	effects.remove(active_effect)


func remove_effects_with_tag(tag: StringName) -> void:
	effects.remove_effects_with_tag(tag)


func remove_effects_from_source(source_node: Node) -> void:
	effects.remove_effects_from_source(source_node)


func get_active_effects() -> Array[ActiveGameplayEffect]:
	return effects.active_effects()


## Whether every attribute this cost touches can pay it in full from its durable
## base.
##
## A temporary buff does not subsidise a durable cost. Mana base 10
## with an active +20 cannot pay 20, because committing -20 to base would be
## reduced by the clamp - and a cost that the clamp had to shrink was not
## affordable, it was merely survivable.
##
## Runs the same evaluator the commit runs, on an isolated spec copy, so the
## preview cannot disagree with the commit and cannot mutate anything.
func can_afford_cost(effect: GameplayEffect, effect_level: float = 1.0) -> bool:
	if effect == null:
		return true

	var context: GameplayEffectContext = GameplayEffectContext.new(get_effect_target())
	var probe: GameplayEffectSpec = GameplayEffectSpec.new(effect, context, effect_level)

	var request: GameplayEffectEvaluator.Request = GameplayEffectEvaluator.Request.new()
	request.spec = probe
	request.attributes = attributes
	request.owner_asc = self
	request.application_order = 0
	request.mode = GameplayEffectEvaluator.Mode.BASE_MUTATION

	var evaluation: GameplayEffectEvaluationResult = GameplayEffectEvaluator.evaluate(request)
	if not evaluation.is_ok():
		return false

	for staged: AttributeBaseMutation in evaluation.base_mutations:
		if not is_equal_approx(staged.committed_base_value, staged.requested_base_value):
			return false
	return true
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
func grant_ability(ability: GameplayAbility) -> void:
	ability_runtime.grant(ability)


func remove_ability(ability: GameplayAbility) -> void:
	ability_runtime.remove(ability)


func can_activate_ability(ability: GameplayAbility, emit_failure: bool = false) -> bool:
	var reason: AbilityRuntime.ActivationError = ability_runtime.activation_error(ability)
	if reason == AbilityRuntime.ActivationError.NONE:
		return true
	if emit_failure:
		ability_activation_failed.emit(ability, reason)
	return false


func cancel_abilities_with_tags(cancel_tags: Array[StringName]) -> void:
	ability_runtime.cancel_with_tags(cancel_tags)


## Route an input slot to a granted ability. False when it was never granted.
##
## The runtime refuses that case and says so; the facade used to drop the
## answer, so a caller binding an ability the ASC does not have was told
## nothing and found out when the press reached no one.
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
	events.dispatch(event, ability_runtime.abilities())
#endregion
