## The five things a client may ask the authority for, and what the authority
## does with each.
##
## An activation request was the only one for a long time, and it lives on the
## runtime with the rest of the conversation. F6.6.3 added five more - an aim, a
## yes, a no, an event and an input - and they are one subject: each is a client
## asking the authority to do something on its behalf, so each is a place a
## client could ask for something it is not entitled to, and each needs the same
## three questions asked of it before anything happens.
##
## Composed into GameplayNetworkRuntime the way GameplayEffectStackingRuntime is
## composed into the effect runtime. The runtime is still the one door to a
## network: what left it is a layer, not a second door.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetRequestRuntime extends RefCounted

var net: GameplayNetworkRuntime = null


## What this machine aimed at, on its way to be checked.
##
## The aim travels as the shape the targeting layer already crosses wires in,
## and the run it belongs to travels with it: an aim with no activation is an
## aim the authority cannot match to anything waiting for one.
func target_data(
	id: GameplayNetEntityId,
	data: GameplayAbilityTargetData,
	activation: GameplayNetActivationId = null,
	key: GameplayPredictionKey = null
) -> GameplayNetMessage:
	if data == null:
		return null
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.TARGET_DATA, id
	)
	message.activation = activation
	message.prediction_key = key
	message.payload[GameplayNetMessage.TARGET_DATA_KEY] = (
		GameplayTargetDataTranslator.to_wire(data, net.registry)
	)
	net.publish(message)
	return message


## The generic yes and no, on their way to whoever is waiting on them.
func generic_confirm(id: GameplayNetEntityId) -> GameplayNetMessage:
	return _bare(GameplayNetMessage.Kind.GENERIC_CONFIRM, id)


func generic_cancel(id: GameplayNetEntityId) -> GameplayNetMessage:
	return _bare(GameplayNetMessage.Kind.GENERIC_CANCEL, id)


## An event, in the one shape events already cross a wire in.
##
## Never a second shape: F6.1.3 decided what an event looks like on a wire, and
## a networking layer that rebuilt one would be two descriptions of an event
## with nothing keeping them in step.
func gameplay_event(
	id: GameplayNetEntityId, event: GameplayEventData
) -> GameplayNetMessage:
	var said: GameplayEventWire = GameplayEventTranslator.to_wire(event, net.registry)
	if said == null:
		return null
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.GAMEPLAY_EVENT, id
	)
	message.payload[GameplayNetMessage.EVENT_KEY] = said.to_wire()
	net.publish(message)
	return message


## An input, for the abilities whose policy says the input crosses rather than
## the activation it would cause.
##
## By definition rather than by handle: a handle is a number one machine made
## up, and an authority resolving a request by it is resolving it by something
## it never agreed to.
func input(
	id: GameplayNetEntityId, definition: Resource, input_id: int, pressed: bool
) -> GameplayNetMessage:
	var named: GameplayNetDefinitionId = net.registry.register_definition(definition)
	if not named.is_valid():
		return null
	var message: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.INPUT_PRESSED if pressed
		else GameplayNetMessage.Kind.INPUT_RELEASED,
		id
	)
	message.definition = named
	message.payload[GameplayNetMessage.INPUT_KEY] = input_id
	net.publish(message)
	return message


## Pressing and letting go of an ability whose input crosses directly.
##
## Two doors rather than one with a flag, because they are reached from
## different places: the press is what `start` sends instead of a request,
## and the release has no activation-shaped opposite to be sent by.
##
## Both name the slot this machine's own grant was bound to. Never a handle:
## the authority resolves the input against the grant it made, and a handle
## is a number the client invented.
func press(
	asc: AbilitySystemComponent, id: GameplayNetEntityId, definition: Resource
) -> GameplayNetMessage:
	return input(id, definition, _slot_for(asc, definition), true)


## Answers whether anything was sent. Nothing is, for an ability that does
## not replicate its input, because there is no release for it to have.
func release(asc: AbilitySystemComponent, definition: Resource) -> bool:
	if net.is_authority() or not GameplayNetAbilityPolicy.replicates_input_directly(
		definition
	):
		return false
	var id: GameplayNetEntityId = net.registry.entity_for(asc)
	if not id.is_valid():
		return false
	return input(id, definition, _slot_for(asc, definition), false) != null


static func _slot_for(asc: AbilitySystemComponent, definition: Resource) -> int:
	var spec: GameplayAbilitySpec = asc.ability_runtime.queries.spec_for_scene(
		definition as PackedScene
	)
	return spec.input_id if spec != null else -1


func _bare(
	kind: GameplayNetMessage.Kind, id: GameplayNetEntityId
) -> GameplayNetMessage:
	var message: GameplayNetMessage = GameplayNetMessage.of(kind, id)
	net.publish(message)
	return message
## An aim a client made, checked before anything is done with it.
##
## Three refusals, in the order a machine can answer them: a claim that does not
## read as an aim at all, one naming somebody who is not here, and one no
## provider of the kind that is waiting could have produced. Only then is it
## handed over.
func honour_target_data(message: GameplayNetMessage) -> bool:
	var asc: AbilitySystemComponent = net.registry.asc_for(message.entity)
	var carried: Variant = message.payload.get(GameplayNetMessage.TARGET_DATA_KEY, {})
	if not carried is Dictionary:
		net._refuse(message, GameplayNetworkRuntime.REASON_TARGET_INVALID)
		return false

	var claimed: Dictionary = carried
	var aim: GameplayAbilityTargetData = GameplayTargetDataTranslator.from_wire(
		claimed, net.registry
	)
	if aim == null:
		net._refuse(message, GameplayNetworkRuntime.REASON_TARGET_INVALID)
		return false

	# A claim that named somebody and resolved to nobody. It is not a place -
	# a place never had an identity to be unknown - so it is a client naming an
	# entity this machine has never registered.
	if _named_nobody(claimed, aim):
		net._refuse(message, GameplayNetworkRuntime.REASON_TARGET_UNKNOWN)
		return false

	var waiting: GameplayTargetProvider = _provider_waiting_on(asc)
	if waiting == null:
		net._refuse(message, GameplayNetworkRuntime.REASON_TARGET_UNREACHABLE)
		return false
	if not waiting.validate_authoritative(aim, asc):
		net._refuse(message, GameplayNetworkRuntime.REASON_TARGET_INVALID)
		return false

	waiting.confirmed.emit(aim)
	return true


## Whether the claim named entities and none of them resolved.
##
## Asked of what arrived rather than of what came back, because the translator
## turns a hit on an unknown entity into a place: the information that somebody
## was named is in the wire and nowhere else.
static func _named_nobody(
	claimed: Dictionary, aim: GameplayAbilityTargetData
) -> bool:
	if not aim.get_target_nodes().is_empty():
		return false
	var hits: Variant = claimed.get(GameplayTargetDataTranslator.HITS_KEY, [])
	if not hits is Array:
		return false
	var listed: Array = hits
	for entry: Variant in listed:
		if not entry is Dictionary:
			continue
		var hit: Dictionary = entry
		if GameplayWireReader.number_in(
			hit, GameplayTargetDataTranslator.ENTITY_KEY, 0
		) != 0:
			return true
	return false


## Which provider on this entity is waiting for an aim.
##
## The first one previewing, because an ability aims one thing at a time: two
## providers previewing at once is a game that started two aims, and answering
## either with the other data is worse than refusing.
static func _provider_waiting_on(asc: AbilitySystemComponent) -> GameplayTargetProvider:
	for provider: GameplayTargetProvider in asc.ability_runtime.queries.previewing_providers():
		return provider
	return null


## An event a client sent, in the one shape events cross a wire in.
func honour_event(message: GameplayNetMessage) -> bool:
	var carried: Variant = message.payload.get(GameplayNetMessage.EVENT_KEY, {})
	if not carried is Dictionary:
		net._refuse(message, GameplayNetworkRuntime.REASON_INCOMPLETE)
		return false
	# Named rather than handed straight over: the guard above proved it is
	# a Dictionary, and the local is where that proof is written down.
	var payload: Dictionary = carried
	var said: GameplayEventWire = GameplayEventWire.from_wire(payload)
	var event: GameplayEventData = GameplayEventTranslator.from_wire(said, net.registry)
	if event == null:
		net._refuse(message, GameplayNetworkRuntime.REASON_INCOMPLETE)
		return false
	net.registry.asc_for(message.entity).send_gameplay_event(event)
	return true


## An input a client sent, resolved to the grant the authority actually made.
##
## By stable definition rather than by the client own handle, which is the whole
## reason the input crosses instead of the activation it would cause: an
## authority resolving a client handle would be trusting a number that client
## invented.
func honour_input(message: GameplayNetMessage) -> bool:
	var definition: Resource = net.registry.definition_for(message.definition)
	if definition == null:
		net._refuse(message, GameplayNetworkRuntime.REASON_UNKNOWN_DEFINITION)
		return false

	# A press starts and a release ends, so the two ask the security policy
	# different questions. An ability the authority alone may start still
	# accepts being let go of, and one the authority alone may end still
	# accepts being pressed - which is why there are two answers and not one.
	var pressed: bool = message.kind == GameplayNetMessage.Kind.INPUT_PRESSED
	var allowed: bool = (
		GameplayNetAuthority.accepts_remote_start(
			GameplayNetAbilityPolicy.security_of(definition)
		) if pressed
		else GameplayNetAuthority.accepts_remote_end(
			GameplayNetAbilityPolicy.security_of(definition),
			GameplayNetAbilityPolicy.respects_remote_cancellation(definition)
		)
	)
	if not allowed:
		net._refuse(message, GameplayNetworkRuntime.REASON_POLICY)
		return false

	var asc: AbilitySystemComponent = net.registry.asc_for(message.entity)
	var slot: int = GameplayWireReader.number_in(
		message.payload, GameplayNetMessage.INPUT_KEY, -1
	)
	if pressed:
		asc.ability_local_input_pressed(slot)
	else:
		asc.ability_local_input_released(slot)
	return true
