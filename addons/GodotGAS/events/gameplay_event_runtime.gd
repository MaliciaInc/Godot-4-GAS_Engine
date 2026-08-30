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
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEventRuntime extends RefCounted


var owner_asc: AbilitySystemComponent = null


#region Dispatch
## Deliver one event to every eligible listener.
##
## The eligible listeners are snapshotted before the first callback runs. A
## listener that grants or removes an ability while handling the event changes
## what the NEXT event sees, never what this one delivers: without the snapshot,
## an ability removed mid-dispatch could make the loop skip its neighbour, and
## one granted mid-dispatch could receive an event it was not present for.
func dispatch(event: GameplayEventData, abilities: Array[GameplayAbility]) -> void:
	if event == null or event.event_tag == &"":
		return

	var listeners: Array[GameplayAbility] = eligible_listeners(event.event_tag, abilities)

	if owner_asc != null:
		owner_asc.gameplay_event_received.emit(event)

	for ability: GameplayAbility in listeners:
		if is_instance_valid(ability):
			ability.try_activate(event.context)


## Every ability whose trigger tag covers this event, as a stable snapshot.
static func eligible_listeners(
	event_tag: StringName, abilities: Array[GameplayAbility]
) -> Array[GameplayAbility]:
	var listeners: Array[GameplayAbility] = []
	for ability: GameplayAbility in abilities:
		if ability == null or ability.trigger_event_tag == &"":
			continue
		if matches(event_tag, ability.trigger_event_tag):
			listeners.append(ability)
	return listeners


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
