## The running game's side of the debugger: watch one entity, say what happens.
##
## An editor plugin that reached into a running game would be reaching across a
## process boundary that does not exist to be reached across. What crosses it is
## messages, and this is what sends them.
##
## Nothing in the engine was changed to make this possible. The component
## already announces everything worth reporting - an ability refused, an effect
## applied, a tag count moved, an attribute changed - so this listens rather
## than instruments. Instrumenting would have meant a second description of what
## happened, written at each site, and the two would disagree the first time one
## of them was updated.
##
## Only in a debug build. `EngineDebugger.is_active()` is false in an exported
## release, so `watch()` attaches nothing and a shipped game carries the cost of
## an `if`.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugChannel extends RefCounted

var _watched: AbilitySystemComponent = null


## Start reporting on `component`, if anything is listening.
##
## Answers whether it attached, so a caller can tell "not debugging" from
## "attached and the entity is quiet" - which look the same from the far end and
## are the first thing somebody wonders about.
func watch(component: AbilitySystemComponent) -> bool:
	if component == null or not EngineDebugger.is_active():
		return false

	_watched = component
	component.ability_granted.connect(_on_ability_granted)
	component.ability_committed.connect(_on_ability_committed)
	component.cue_executed.connect(_on_cue_executed)
	component.ability_activated.connect(_on_ability_activated)
	component.ability_runtime_ended.connect(_on_ability_ended)
	component.ability_activation_failed.connect(_on_ability_refused)
	component.active_effect_added.connect(_on_effect_applied)
	component.effect_application_refused.connect(_on_effect_refused)
	component.gameplay_effect_executed.connect(_on_effect_ticked)
	component.gameplay_effect_removal_finished.connect(_on_effect_removed)
	component.tag_count_changed.connect(_on_tag_count_changed)
	component.attribute_changed.connect(_on_attribute_changed)
	send_snapshot()
	return true


## Stop reporting. Every connection this made, taken back - a component that
## outlives the channel and still holds callables into it is the shape of leak
## the whole dispose() work in F5.1.2 was about.
func stop() -> void:
	if _watched == null:
		return
	_watched.ability_granted.disconnect(_on_ability_granted)
	_watched.ability_committed.disconnect(_on_ability_committed)
	_watched.cue_executed.disconnect(_on_cue_executed)
	_watched.ability_activated.disconnect(_on_ability_activated)
	_watched.ability_runtime_ended.disconnect(_on_ability_ended)
	_watched.ability_activation_failed.disconnect(_on_ability_refused)
	_watched.active_effect_added.disconnect(_on_effect_applied)
	_watched.effect_application_refused.disconnect(_on_effect_refused)
	_watched.gameplay_effect_executed.disconnect(_on_effect_ticked)
	_watched.gameplay_effect_removal_finished.disconnect(_on_effect_removed)
	_watched.tag_count_changed.disconnect(_on_tag_count_changed)
	_watched.attribute_changed.disconnect(_on_attribute_changed)
	_watched = null


#region What an entity looks like right now
## Send everything about the watched component as it stands.
##
## Sent whole rather than as a stream of changes. A debugger that rebuilt state
## from events is a debugger that is wrong for as long as it was not listening,
## which includes every moment before somebody opened it.
func send_snapshot() -> void:
	if _watched == null:
		return
	EngineDebugger.send_message(GasDebugMessage.SNAPSHOT, [snapshot_of(_watched)])


## One component, as a plain Dictionary.
##
## Plain because it crosses a process boundary: an object would arrive as an
## object of a class the editor may not have loaded, and a Node reference would
## arrive as nothing at all.
static func snapshot_of(component: AbilitySystemComponent) -> Dictionary:
	var said: Dictionary = {}
	said[GasDebugMessage.ASC_ID] = component.get_instance_id()
	said[GasDebugMessage.OWNER] = _named(component.get_parent())
	said[GasDebugMessage.AVATAR] = _named(component.get_effect_target())
	said[GasDebugMessage.ATTRIBUTES] = _attributes_of(component)
	said[GasDebugMessage.TAGS] = _tags_of(component)
	said[GasDebugMessage.ABILITIES] = _abilities_of(component)
	said[GasDebugMessage.EFFECTS] = _effects_of(component)
	return said


static func _named(node: Node) -> String:
	return String(node.name) if node != null else ""


static func _attributes_of(component: AbilitySystemComponent) -> Array:
	var said: Array = []
	for attribute_name: StringName in component.attributes.all_attribute_names():
		said.append({
			GasDebugMessage.NAME: String(attribute_name),
			GasDebugMessage.BASE: component.get_attribute_base(attribute_name),
			GasDebugMessage.CURRENT: component.get_attribute_current(attribute_name),
		})
	return said


## Both counts, because they are two questions: how many effects grant this
## exact tag, and how much of the family is held. A debugger showing one of them
## is a debugger somebody has to do arithmetic in front of - `State` reading 0
## while `State.Stunned` reads 2 is a person working out the hierarchy by hand.
static func _tags_of(component: AbilitySystemComponent) -> Array:
	var said: Array = []
	var families: Array[StringName] = []
	for tag: StringName in component.tags.active_tags():
		said.append({
			GasDebugMessage.NAME: String(tag),
			GasDebugMessage.COUNT: component.tags.count_exact(tag),
			GasDebugMessage.FAMILY_COUNT: component.tags.count(tag),
		})
		for ancestor: StringName in GameplayTagRuntime.ancestors_of(tag):
			if ancestor != tag and not families.has(ancestor):
				families.append(ancestor)

	# A parent nothing holds directly is still something a listener watches, and
	# a debugger that only listed what is written on the entity would leave the
	# person to work out that `State` is held at all.
	for ancestor: StringName in families:
		said.append({
			GasDebugMessage.NAME: String(ancestor),
			GasDebugMessage.COUNT: component.tags.count_exact(ancestor),
			GasDebugMessage.FAMILY_COUNT: component.tags.count(ancestor),
		})
	return said


## By handle, which is what a grant is: the instance behind it comes and goes.
static func _abilities_of(component: AbilitySystemComponent) -> Array:
	var said: Array = []
	for spec: GameplayAbilitySpec in component.ability_runtime.specs():
		said.append({
			GasDebugMessage.HANDLE: spec.handle.id,
			GasDebugMessage.NAME: spec.definition.ability_name,
			GasDebugMessage.LEVEL: spec.level,
			GasDebugMessage.ACTIVE: spec.active_count,
		})
	return said


static func _effects_of(component: AbilitySystemComponent) -> Array:
	var said: Array = []
	for active: ActiveGameplayEffect in component.get_active_effects():
		said.append({
			GasDebugMessage.HANDLE: active.handle.id if active.handle != null else 0,
			GasDebugMessage.NAME: String(active.get_effect_def().resource_name),
			GasDebugMessage.STACKS: active.stack_count,
			GasDebugMessage.SECONDS_LEFT: active.time_remaining,
			GasDebugMessage.TURNS_LEFT: component.get_effect_turns_remaining(active.handle),
		})
	return said
#endregion


#region What just happened
## Say that something happened, to whoever is listening.
##
## Public so a game can report something of its own through the same channel -
## a custom task, an integration's own step - rather than being told the
## debugger only understands the engine.
func trace(kind: GasDebugMessage.Kind, subject: String, detail: String = "") -> void:
	if _watched == null:
		return
	EngineDebugger.send_message(GasDebugMessage.TRACE, [{
		GasDebugMessage.KIND: int(kind),
		GasDebugMessage.ASC_ID: _watched.get_instance_id(),
		GasDebugMessage.SUBJECT: subject,
		GasDebugMessage.DETAIL: detail,
	}])


func _on_ability_granted(handle: GameplayAbilityHandle) -> void:
	trace(GasDebugMessage.Kind.ABILITY_GRANTED, str(handle.id))


func _on_ability_committed(
	handle: GameplayAbilityHandle, result: AbilityCommitResult
) -> void:
	trace(
		GasDebugMessage.Kind.ABILITY_COMMITTED,
		str(handle.id),
		GasDebugMessage.key_of(AbilityCommitResult.Status.keys(), int(result.status))
	)


func _on_cue_executed(cue_tag: StringName) -> void:
	trace(GasDebugMessage.Kind.CUE_EXECUTED, String(cue_tag))


func _on_ability_activated(handle: GameplayAbilityHandle, _instance: GameplayAbility) -> void:
	trace(GasDebugMessage.Kind.ABILITY_ACTIVATED, str(handle.id))


func _on_ability_ended(
	handle: GameplayAbilityHandle,
	_instance: GameplayAbility,
	was_cancelled: bool,
	reason: GameplayAbilityTask.CancelReason
) -> void:
	# Cancelled and ended are the same moment with different causes, and which it
	# was is the first thing somebody asks - so the reason is only worth carrying
	# when there was one.
	var why: String = (
		GasDebugMessage.key_of(GameplayAbilityTask.CancelReason.keys(), int(reason))
		if was_cancelled
		else ""
	)
	trace(GasDebugMessage.Kind.ABILITY_ENDED, str(handle.id), why)


func _on_ability_refused(
	ability: GameplayAbility, reason: AbilityRuntime.ActivationError
) -> void:
	trace(
		GasDebugMessage.Kind.ABILITY_REFUSED,
		_named(ability),
		GasDebugMessage.key_of(AbilityRuntime.ActivationError.keys(), int(reason))
	)


func _on_effect_applied(active: ActiveGameplayEffect) -> void:
	trace(GasDebugMessage.Kind.EFFECT_APPLIED, String(active.get_effect_def().resource_name))


func _on_effect_refused(
	status: AttributeEvaluationResult.Status, attribute_name: StringName
) -> void:
	trace(
		GasDebugMessage.Kind.EFFECT_REFUSED,
		String(attribute_name),
		GasDebugMessage.key_of(AttributeEvaluationResult.Status.keys(), int(status))
	)


func _on_effect_ticked(_spec: GameplayEffectSpec, active: ActiveGameplayEffect) -> void:
	trace(GasDebugMessage.Kind.EFFECT_TICKED, String(active.get_effect_def().resource_name))


func _on_effect_removed(
	active: ActiveGameplayEffect, reason: ActiveGameplayEffect.RemovalReason
) -> void:
	trace(
		GasDebugMessage.Kind.EFFECT_REMOVED,
		String(active.get_effect_def().resource_name),
		GasDebugMessage.key_of(ActiveGameplayEffect.RemovalReason.keys(), int(reason))
	)


func _on_tag_count_changed(tag: StringName, new_count: int) -> void:
	trace(GasDebugMessage.Kind.TAG_COUNT_CHANGED, String(tag), str(new_count))


func _on_attribute_changed(
	attribute_name: StringName, old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	trace(
		GasDebugMessage.Kind.ATTRIBUTE_CHANGED,
		String(attribute_name),
		"%s -> %s" % [old_value, new_value]
	)
#endregion
