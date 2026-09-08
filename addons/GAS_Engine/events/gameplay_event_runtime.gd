## Dispatch of gameplay events to the abilities listening for them.
##
## Matching is hierarchical in one direction only. A listener on `Event.Damage`
## receives `Event.Damage`, `Event.Damage.Critical` and
## `Event.Damage.Critical.Fire`. It does not receive `Event.Damages` or
## `Event.Damageable`, because the separator is part of the rule. A listener on
## `Event.Damage.Critical.Fire` does not receive the broader
## `Event.Damage.Critical`: a listener asks for a subtree, not for an ancestor.
##
## The payload is a typed GameplayEventData. Upstream passed `Variant`, so every
## listener decided for itself what the payload was and a wrong guess read as
## null instead of failing.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEventRuntime extends RefCounted


var owner_asc: AbilitySystemComponent = null

## Where an eligible spec's activation is actually requested. Dispatch never
## touches a per_actor_instance directly - it asks the runtime by spec, which
## is what lets a later instancing policy answer this without event routing
## having to change again.
var ability_runtime: AbilityRuntime = null


#region Dispatch
## Deliver one event to every eligible listener.
##
## The eligible listeners are snapshotted before the first callback runs. A
## listener that grants or removes an ability while handling the event changes
## what the NEXT event sees, never what this one delivers: without the snapshot,
## an ability removed mid-dispatch could make the loop skip its neighbour, and
## one granted mid-dispatch could receive an event it was not present for.
func dispatch(event: GameplayEventData, specs: Array[GameplayAbilitySpec]) -> void:
	if event == null or event.event_tag == &"":
		return

	_snapshot_tags(event)

	var listeners: Array[GameplayAbilitySpec] = eligible_listeners(event.event_tag, specs)

	if owner_asc != null:
		owner_asc.gameplay_event_received.emit(event)

	for spec: GameplayAbilitySpec in listeners:
		if not _wanted_by(spec, event):
			continue
		_activate(spec, event)


## By handle through the canonical AbilityRuntime.try_activate(), the same
## path input routing and passives use - it already resolves/creates the
## right instance for either instancing policy, so a PER_EXECUTION listener
## wakes without a per-actor template ever existing, with no branch here.
## Freeze what the two parties had on them, at the one moment that answers it.
##
## Taken here rather than in each listener for the reason the fields exist:
## every listener recomputing them would be several answers to one question,
## each about whenever that listener happened to run. A sender that filled
## them in itself is left alone - it knew something this does not.
static func _snapshot_tags(event: GameplayEventData) -> void:
	if event.instigator_tags.is_empty():
		event.instigator_tags = _tags_of(event.instigator)
	if event.target_tags.is_empty():
		event.target_tags = _tags_of(event.target)


## What a node's ability system currently holds, or nothing at all.
##
## Nothing at all stays empty: an absence is not a tag that matches nothing,
## and a query asked about the two gets different answers.
static func _tags_of(node: Node) -> Array[StringName]:
	if node == null or not is_instance_valid(node):
		return [] as Array[StringName]
	var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(node)
	if asc == null:
		return [] as Array[StringName]
	return asc.tags.active_tags()


## Whether the ability behind this spec wants the event right now.
##
## Asked of the running instance when there is one and of nothing otherwise:
## a spec with no instance yet has no state to answer from, and instantiating
## one to ask would be starting the ability to find out whether to start it.
static func _wanted_by(spec: GameplayAbilitySpec, event: GameplayEventData) -> bool:
	var instance: GameplayAbility = spec.per_actor_instance
	if instance == null or not is_instance_valid(instance):
		return true
	return instance.should_respond_to_event(event)


func _activate(spec: GameplayAbilitySpec, event: GameplayEventData) -> void:
	if ability_runtime != null:
		ability_runtime.try_activate_from_event(spec.handle, event)


## Every ON_GAMEPLAY_EVENT spec with a trigger covering this event, as a
## stable snapshot. MANUAL/ON_GRANTED/PASSIVE specs never listen this way,
## even if a scene happened to leave gameplay_event_triggers populated.
static func eligible_listeners(
	event_tag: StringName, specs: Array[GameplayAbilitySpec]
) -> Array[GameplayAbilitySpec]:
	var listeners: Array[GameplayAbilitySpec] = []
	for spec: GameplayAbilitySpec in specs:
		if spec == null or spec.definition == null:
			continue
		if spec.definition.activation_policy != GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT:
			continue
		if _any_trigger_matches(spec.definition.gameplay_event_triggers, event_tag):
			listeners.append(spec)
	return listeners


## A trigger's event_query is matched against a single-element tag set
## holding the event's own tag - the same GameplayTagQuery hierarchy rule
## `matches()` below implements for a bare tag, reused rather than
## reimplemented for a query.
static func _any_trigger_matches(
	triggers: Array[GameplayAbilityEventTrigger], event_tag: StringName
) -> bool:
	for trigger: GameplayAbilityEventTrigger in triggers:
		if trigger == null or trigger.event_query == null:
			continue
		# A trigger declared against a tag transition is not an event listener,
		# even when the tag it names would match an event's own tag. The two
		# sources ask different questions of the same query.
		if trigger.source != GameplayAbilityEventTrigger.Source.GAMEPLAY_EVENT:
			continue
		if trigger.event_query.matches_tags([event_tag]):
			return true
	return false


## Whether an event reaches a listener.
##
## Deliberately the same rule as GameplayTagRuntime.is_descendant_of, and
## deliberately called through it rather than reimplemented: tags and events
## share one hierarchy contract, and two copies of it would drift the first time
## either was tuned.
static func matches(event_tag: StringName, listener_tag: StringName) -> bool:
	return GameplayTagRuntime.is_descendant_of(event_tag, listener_tag)
#endregion


#region Construction
## Build the event an effect broadcasts, so the six fields are populated in one
## place rather than at each of the call sites that fire one.
static func from_spec(event_tag: StringName, spec: GameplayEffectSpec, target: Node) -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = event_tag
	event.target = target
	event.context = spec.context
	if spec.context != null:
		event.instigator = spec.context.instigator
	return event
#endregion
