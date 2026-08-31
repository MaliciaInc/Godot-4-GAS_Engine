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

	var listeners: Array[GameplayAbilitySpec] = eligible_listeners(event.event_tag, specs)

	if owner_asc != null:
		owner_asc.gameplay_event_received.emit(event)

	for spec: GameplayAbilitySpec in listeners:
		_activate(spec, event.context)


## By handle through the canonical AbilityRuntime.try_activate(), the same
## path input routing and passives use - it already resolves/creates the
## right instance for either instancing policy, so a PER_EXECUTION listener
## wakes without a per-actor template ever existing, with no branch here.
func _activate(spec: GameplayAbilitySpec, context: GameplayEffectContext) -> void:
	if ability_runtime != null:
		ability_runtime.try_activate(spec.handle, context)


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
		if trigger != null and trigger.event_query != null and trigger.event_query.matches_tags([event_tag]):
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
