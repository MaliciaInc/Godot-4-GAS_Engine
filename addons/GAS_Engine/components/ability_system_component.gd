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
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name AbilitySystemComponent extends Node

#region Signals
## A tag's count went from zero to one.
signal tag_added(tag: StringName)

## A tag's count changed while staying above zero.
signal tag_count_changed(tag: StringName, new_count: int)

## A tag's count reached zero and it was dropped.
signal tag_removed(tag: StringName)

## A tag, or anything under it, changed count. Unreal's AnyCountChange.
signal tag_or_child_count_changed(tag: StringName, new_count: int)

## A tag, or anything under it, appeared or went away. Unreal's NewOrRemoved.
signal tag_or_child_presence_changed(tag: StringName, present: bool)

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
## An ability was granted. The moment a handle starts naming something.
signal ability_granted(handle: GameplayAbilityHandle)

## An ability paid for itself and started its cooldowns, or did not.
##
## The moment an activation becomes irreversible, and the one somebody debugging
## a cost asks about: it is where the resources went and where the cooldown
## began, and a listener could see neither before.
signal ability_committed(handle: GameplayAbilityHandle, result: AbilityCommitResult)

## A one-shot cue was played on this entity.
signal cue_executed(cue_tag: StringName)

signal ability_activated(handle: GameplayAbilityHandle, instance: GameplayAbility)

## The body an ability happens to has been swapped for another one.
##
## Announced rather than discovered: an ability holding a reference to the
## old avatar has to be told, and polling for it would mean every ability
## checking every frame whether the world moved under it.
signal ability_actor_info_changed(old_avatar: Node, new_avatar: Node)

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

@export_category("Compatibility")
## Which set of contracts this component answers by.
##
## The default stays GODOT_NATIVE, and has to: a phase cannot change what an
## existing project already does by being installed. A component only follows
## Unreal's contract where they differ once somebody asks for it here.
@export var compatibility_profile: GameplayCompatibilityProfile = GameplayCompatibilityProfile.new()
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

## Who these abilities belong to, and who they happen to.
var actor_info: GameplayAbilityActorInfo = GameplayAbilityActorInfo.new()

## Set once, by dispose(). A second teardown must not run: the first one
## already severed the references the second would walk.
var _disposed: bool = false

#region Lifecycle
## Says what happens here to whoever is debugging, and nothing at all when
## nobody is. See GasDebugChannel: it listens to this component's own signals
## rather than being reported to from inside the runtimes, so there is one
## description of what happened rather than two that can disagree.
var debug_channel: GasDebugChannel = GasDebugChannel.new()


func _ready() -> void:
	_wire_runtimes()
	# The entity this component hangs under, unless somebody said otherwise
	# before it entered the tree. Owner and avatar both, which is what every
	# project that never thinks about avatars gets and always got.
	if actor_info.owner == null:
		actor_info.initialize(get_parent(), get_parent())
	_adopt_attribute_sets()
	# Every entity is inspectable while something is listening, and none of them
	# has to be wired up for it: a debugger somebody has to remember to attach is
	# a debugger that is not attached the one time it was needed. `watch()`
	# answers false and connects nothing when nothing is listening, which is
	# every exported build.
	debug_channel.watch(self)


## Whether this component answers by Unreal's contracts where they differ.
##
## Asked by the runtimes rather than decided by them: two runtimes reading the
## same profile agree, and two runtimes each deciding what "compatible" means
## do not.
func uses_ue_5_7_contracts() -> bool:
	return compatibility_profile != null and compatibility_profile.is_ue_5_7()


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
## @composer
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


## Terminal teardown. cleanup() remains a reusable reset for a live ASC.
func dispose() -> void:
	if _disposed:
		return

	cleanup()
	debug_channel.stop()

	scheduler.effects = null

	events.owner_asc = null
	events.ability_runtime = null

	ability_runtime.dispose()
	effects.dispose()

	attributes.owner_node = null
	actor_info.clear()
	_disposed = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		dispose()
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
	_emit_hierarchical_tag_change(tag, change)
	effects.on_owner_tags_changed()
	ability_runtime.request_passive_reevaluation()


## The parent-aware half of a tag change: a listener watching `State` hears
## about `State.Stunned`, which is what a hierarchy is for.
##
## Presence is announced only where the hierarchical count actually crossed
## zero. Adding `State.Rooted` beside an existing `State.Stunned` takes `State`
## from one to two, and a listener treating every count change as "it is held
## now" would fire twice for one condition and act on the second one.
##
## The crossing is read off the change rather than off a before-and-after
## snapshot: only ADDED can take an ancestor to one, and only REMOVED can take
## it to zero, because every other change moves the count by one from at
## least one.
func _emit_hierarchical_tag_change(
	tag: StringName, change: GameplayTagRuntime.Change
) -> void:
	if change == GameplayTagRuntime.Change.NONE:
		return
	var added: bool = change == GameplayTagRuntime.Change.ADDED
	var removed: bool = change == GameplayTagRuntime.Change.REMOVED
	for ancestor: StringName in GameplayTagRuntime.ancestors_of(tag):
		var total: int = tags.count(ancestor)
		tag_or_child_count_changed.emit(ancestor, total)
		if added and total == 1:
			tag_or_child_presence_changed.emit(ancestor, true)
		elif removed and total == 0:
			tag_or_child_presence_changed.emit(ancestor, false)


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


## Who these abilities belong to, and who they happen to.
##
## The component stays where the grants are; the avatar is what effects and
## cues act on, and it may be swapped for another body at any time. Whoever
## held the old one is told, because an ability polling for it would be every
## ability asking every frame whether the world moved.
func init_ability_actor_info(owner: Node, avatar: Node = null, controller: Node = null) -> void:
	var old_avatar: Node = actor_info.avatar
	actor_info.initialize(owner, avatar, controller)
	if old_avatar == actor_info.avatar:
		return

	# Every granted ability is told directly as well as through the signal. An
	# ability holding the old body is the thing most likely to act on a corpse,
	# and asking it to subscribe to its own component to find out would be a
	# subscription every ability has to remember to make.
	for spec: GameplayAbilitySpec in ability_runtime.specs():
		if spec.per_actor_instance != null:
			spec.per_actor_instance.on_avatar_changed(old_avatar, actor_info.avatar)
	ability_actor_info_changed.emit(old_avatar, actor_info.avatar)


## The node cues and effects act on.
##
## The avatar when there is one, the owner when the avatar has been freed,
## and the parent when nobody set either - which is every project that never
## thinks about avatars, and is what this answered before there were any.
## @composer
func get_effect_target() -> Node:
	if actor_info != null and is_instance_valid(actor_info.avatar):
		return actor_info.avatar
	if actor_info != null and is_instance_valid(actor_info.owner):
		return actor_info.owner
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
## @composer
func execute_cue(params: GameplayCueParams) -> void:
	if params == null:
		return
	if params.target == null:
		params.target = get_effect_target()
	var manager: CueManagerScript = _cue_manager()
	if manager != null:
		manager.execute_cue(params)
	cue_executed.emit(params.cue_tag)


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
## @composer
func get_attribute(attribute_name: StringName) -> AttributeData:
	return attributes.find(attribute_name)


## @composer
func has_attribute(attribute_name: StringName) -> bool:
	return attributes.has(attribute_name)


## @composer
func get_attribute_base(attribute_name: StringName) -> float:
	return attributes.get_base_value(attribute_name)


## @composer
func get_attribute_current(attribute_name: StringName) -> float:
	return attributes.get_current_value(attribute_name)


## The one durable-mutation path. No gameplay code writes `current_value`.
## @composer
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


## @composer
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
## @composer
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
## @composer
func apply_effect_spec(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	return apply_effect_spec_result(spec).active_effect

## Apply an effect to another ASC, giving that target its own spec copy.
## Captures are prepared here, on the shared spec, before it is copied - taken
## later, inside the copy's own apply, a SOURCE+SNAPSHOT would be one target's
## read, not the shared one every target needs.
## @composer
## @composer_name: Apply Spec To Target, With Result
func apply_effect_spec_to_target_result(
	spec: GameplayEffectSpec,
	target_asc: AbilitySystemComponent,
	aimed_at: GameplayAbilityTargetData = null
) -> GameplayEffectApplicationResult:
	if target_asc == null or spec == null:
		return GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.INVALID_SPEC, spec)
	if not spec.prepare_captures(self):
		return GameplayEffectApplicationResult.failure(GameplayEffectApplicationResult.Status.EVALUATION_FAILED, spec)
	# `aimed_at` is this victim's share of the aim, and null for an effect that
	# was not aimed at anything - which is most of them.
	var result: GameplayEffectApplicationResult = target_asc.apply_effect_spec_result(
		spec.create_application_copy_for(aimed_at)
	)
	if result.is_ok():
		effect_applied_to_target.emit(target_asc, spec)
	return result

## @composer
func apply_effect_spec_to_target(
	spec: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> ActiveGameplayEffect:
	return apply_effect_spec_to_target_result(spec, target_asc).active_effect

## @composer
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

## @composer
func apply_gameplay_effect(
	effect: GameplayEffect, source_asc: AbilitySystemComponent = null, effect_level: float = 1.0
) -> ActiveGameplayEffect:
	return apply_gameplay_effect_result(effect, source_asc, effect_level).active_effect


## @composer
func remove_active_effect(active_effect: ActiveGameplayEffect) -> void:
	effects.remove(active_effect)

## @composer
func get_active_effect(handle: GameplayEffectHandle) -> ActiveGameplayEffect:
	return effects.handles.resolve(handle)

## @composer
func find_active_effects(query: GameplayEffectQuery) -> Array[ActiveGameplayEffect]:
	return effects.handles.find(query)

## @composer
func find_active_effect_handles(query: GameplayEffectQuery) -> Array[GameplayEffectHandle]:
	return effects.handles.find_handles(query)

## @composer
func count_active_effects(query: GameplayEffectQuery) -> int:
	return effects.handles.count(query)

## Change what a running effect is worth, by handle.
##
## The five doors the phase names. What each of them means is
## `GameplayEffectMutations`: this is the surface, and a surface with the work
## in it is a component that grows every time anything new can be done.
## @composer
func set_active_effect_level(
	handle: GameplayEffectHandle, level: float
) -> GameplayEffectMutationResult:
	return GameplayEffectMutations.set_level(effects, handle, level)


## @composer
func set_active_effect_stack_count(
	handle: GameplayEffectHandle, count: int
) -> GameplayEffectMutationResult:
	return GameplayEffectMutations.set_stack_count(effects, handle, count)


## @composer
func remove_active_effect_stacks(
	handle: GameplayEffectHandle, count: int
) -> GameplayEffectMutationResult:
	return GameplayEffectMutations.remove_stacks(effects, handle, count)


## @composer
## @composer_name: Set A Caller-Supplied Value
func update_active_effect_set_by_caller(
	handle: GameplayEffectHandle, tag: StringName, value: float
) -> GameplayEffectMutationResult:
	return GameplayEffectMutations.update_set_by_caller(effects, handle, tag, value)


## @composer
func set_active_effect_duration(
	handle: GameplayEffectHandle, seconds: float
) -> GameplayEffectMutationResult:
	return GameplayEffectMutations.set_duration(effects, handle, seconds)


## @composer
func remove_active_effects(query: GameplayEffectQuery) -> int:
	return effects.handles.remove_matching(query)

## @composer
func remove_active_effect_by_handle(handle: GameplayEffectHandle) -> bool:
	return effects.handles.remove_by_handle(handle)

## @composer
func get_effect_duration_remaining(handle: GameplayEffectHandle) -> float:
	return effects.handles.duration_remaining(handle)

## @composer
func get_effect_turns_remaining(handle: GameplayEffectHandle) -> int:
	return effects.handles.turns_remaining(handle)

## @composer
func remove_effects_with_tag(tag: StringName) -> void:
	effects.remove_effects_with_tag(tag)

## @composer
func remove_effects_from_source(source_node: Node) -> void:
	effects.remove_effects_from_source(source_node)

## @composer
func get_active_effects() -> Array[ActiveGameplayEffect]:
	return effects.active_effects()


## Whether every attribute this cost touches can pay it in full from its
## durable base. `GameplayEffectEvaluator.can_afford()` carries the why, and
## runs the very request a commit runs, so a preview cannot disagree with it.
## @composer
func can_afford_cost(effect: GameplayEffect, effect_level: float = 1.0) -> bool:
	return GameplayEffectEvaluator.can_afford(effect, effect_level, self)
#endregion


#region Tags
## @composer
func add_tag(tag: StringName) -> void:
	emit_tag_change(tag, tags.add(tag), tags.count_exact(tag))


## @composer
func remove_tag(tag: StringName) -> void:
	emit_tag_change(tag, tags.remove(tag), tags.count_exact(tag))


## @composer
func clear_tag(tag: StringName) -> void:
	emit_tag_change(tag, tags.clear(tag), 0)


## @composer
func has_tag_exact(tag: StringName) -> bool:
	return tags.has_exact(tag)


## @composer
func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## @composer
func has_any_tags(query: Array[StringName]) -> bool:
	return tags.has_any(query)


## @composer
func has_all_tags(query: Array[StringName]) -> bool:
	return tags.has_all(query)


## Seconds left on a tag, or INF when something grants it with no end.
## @composer
func get_tag_duration_remaining(tag: StringName) -> float:
	return effects.tag_duration_remaining(tag)


## Turns left on a tag. Seconds and turns are different units and get different
## questions, so a UI cannot count a turn-based debuff down in seconds.
## @composer
func get_tag_turns_remaining(tag: StringName) -> int:
	return effects.tag_turns_remaining(tag)
#endregion


#region Abilities, input and events
## Grant an ability from its scene - the one way an ability is ever granted.
## prepare -> commit under the hood; a failed prepare frees whatever it
## instantiated rather than leaving a Node nobody owns.
## @composer
func give_ability(
	ability_scene: PackedScene,
	level: float = 1.0,
	input_id: int = -1,
	source: GameplayAbilitySource = null
) -> GameplayAbilityHandle:
	return ability_runtime.give_ability(ability_scene, level, input_id, source)


## What a handle was granted, or null when it names nothing here.
##
## The receipt is the identity. A running instance is a thing that exists for as
## long as one activation lasts; the grant outlives every one of them, and a
## caller holding an instance to remember which ability it meant is holding the
## shorter-lived of the two.
## @composer
func get_ability_spec(handle: GameplayAbilityHandle) -> GameplayAbilitySpec:
	return ability_runtime.get_spec(handle)


## Take a grant back. False when the handle names nothing here.
## @composer
func remove_ability_handle(
	handle: GameplayAbilityHandle,
	policy: AbilityRuntime.AbilityRemovalPolicy = AbilityRuntime.AbilityRemovalPolicy.CANCEL_IMMEDIATELY
) -> bool:
	return ability_runtime.remove_ability(handle, policy)


## Start what a handle names, and say what happened.
##
## The result object, not a bool: "it did not start" has half a dozen reasons
## and a caller that has to guess which will guess wrong on the one that
## matters. A null context is an activation with nothing to say about itself,
## which is most of them.
## @composer
func try_activate_ability_handle(
	handle: GameplayAbilityHandle, context: GameplayAbilityActivationContext = null
) -> GameplayAbilityActivationResult:
	return ability_runtime.try_activate_with(handle, context)


## Whether what a handle names could start right now.
## @composer
func can_activate_ability_handle(
	handle: GameplayAbilityHandle, emit_failure: bool = false
) -> bool:
	return ability_runtime.can_activate_spec(
		ability_runtime.get_spec(handle), null, emit_failure
	)


## Route an input slot to a grant. False when it was never granted here.
## @composer
func bind_ability_handle_to_input(
	handle: GameplayAbilityHandle, input_id: int, unbind_others: bool = true
) -> bool:
	return ability_runtime.bind_spec_to_input(
		ability_runtime.get_spec(handle), input_id, unbind_others
	)


## Deprecated: use remove_ability_handle(). Kept for a caller holding the
## running instance, and holding nothing of its own - every one of these three
## resolves the grant behind the instance and asks the door above.
## @composer
## @composer_deprecated: use remove_ability_handle(): a grant outlives its instance
func remove_ability(ability: GameplayAbility) -> void:
	remove_ability_handle(ability.get_ability_handle() if ability != null else null)


## Deprecated: use can_activate_ability_handle(). The instance it was handed is
## the one a refusal names, because that is the one the caller is waiting to
## hear about.
## @composer
## @composer_deprecated: use can_activate_ability_handle() for the same reason
func can_activate_ability(ability: GameplayAbility, emit_failure: bool = false) -> bool:
	return ability_runtime.can_activate_spec(
		ability.current_spec if ability != null else null, ability, emit_failure
	)


## @composer
func cancel_abilities_with_tags(cancel_tags: Array[StringName]) -> void:
	ability_runtime.cancel_with_tags(cancel_tags)


## Deprecated: use bind_ability_handle_to_input().
##
## The runtime refuses and says so; the facade used to drop the answer, so a
## caller binding an ungranted ability found out only when the press reached no one.
## @composer
## @composer_deprecated: use bind_ability_handle_to_input(): a binding is on the grant
func bind_ability_to_input(
	ability: GameplayAbility, input_id: int, unbind_others: bool = true
) -> bool:
	return ability_runtime.bind_to_input(ability, input_id, unbind_others)


## @composer
## @composer_name: Input Pressed
func ability_local_input_pressed(input_id: int) -> void:
	ability_runtime.input_pressed(input_id)


## @composer
## @composer_name: Input Released
func ability_local_input_released(input_id: int) -> void:
	ability_runtime.input_released(input_id)


func register_ability_task(task: GameplayAbilityTask) -> GameplayAbilityTask:
	return ability_runtime.register_task(task)


## These two stay addressed by instance, and are not deprecated for it: a task
## belongs to one activation and target data is delivered into one, so there is
## no grant-shaped question either of them could be asked instead.
## @composer
func cancel_ability_tasks(ability: GameplayAbility, reason: GameplayAbilityTask.CancelReason) -> void:
	ability_runtime.cancel_tasks_for_ability(ability, reason)


## @composer
func submit_ability_target_data(ability: GameplayAbility, data: GameplayAbilityTargetData) -> void:
	ability_runtime.submit_target_data(ability, data)


## @composer
func send_gameplay_event(event: GameplayEventData) -> void:
	# A task already waiting for this event hears it before it can wake a
	# sleeping ability that would then wait for the same one.
	ability_runtime.tasks.gameplay_event(event)
	events.dispatch(event, ability_runtime.specs())
#endregion
