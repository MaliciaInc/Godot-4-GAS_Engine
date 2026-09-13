## Granting an ability, asking to run one, and answering that ask.
##
## The one conversation `GameplayNetworkRuntime` used to hold in full: a grant
## the authority makes, a request a client sends because of it, and the
## confirm or reject that closes the loop. Composed into the runtime the way
## `GameplayNetRequestRuntime` is for everything else a client may ask for -
## split out once this and the identity work AUD-02 added no longer fit
## beside it under the LOC cap, not because the conversation itself grew.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetActivationRuntime extends RefCounted

var net: GameplayNetworkRuntime = null

## The authority's count of runs per entity, which is what an activation id
## is made of.
var _runs: Dictionary[int, int] = {}


## Forget one entity's run count. An id reused by a different character
## starts its first run at 1 rather than continuing whoever had it before.
func forget(id: GameplayNetEntityId) -> void:
	_runs.erase(id.value)


## Forget every entity's run count, for a runtime being torn down whole.
func clear() -> void:
	_runs.clear()


#region What the authority says
## Grant an ability to an entity, and tell the peers.
##
## Refused on a client, and not politely: a client granting itself an ability
## is the bug this whole layer exists to make impossible, so it is refused at
## the one place a grant can be made rather than checked for afterwards.
func grant(id: GameplayNetEntityId, definition: Resource) -> bool:
	return _author(GameplayNetMessage.Kind.GRANT, id, definition)


func revoke(id: GameplayNetEntityId, definition: Resource) -> bool:
	return _author(GameplayNetMessage.Kind.REVOKE, id, definition)


func _author(
	kind: GameplayNetMessage.Kind, id: GameplayNetEntityId, definition: Resource
) -> bool:
	if not GameplayNetAuthority.may_author(net.role):
		return false
	var named: GameplayNetDefinitionId = net.registry.register_definition(definition)
	if not named.is_valid() or net.registry.asc_for(id) == null:
		return false

	var message: GameplayNetMessage = GameplayNetMessage.of(kind, id)
	message.definition = named
	net.publish(message)
	return true
#endregion


#region What a client asks for
## Ask to activate, or run it, or neither - whichever the grant's policy says.
##
## Answers what was done rather than whether it worked, because "run it here"
## and "ask and wait" are both success and a caller that could not tell them
## apart would have to guess whether anything had happened yet.
func start(asc: AbilitySystemComponent, definition: Resource) -> GameplayNetAuthority.Start:
	var spec_policy: GameplayAbility.NetExecutionPolicy = (
		GameplayNetAbilityPolicy.execution_of(definition)
	)
	var decided: GameplayNetAuthority.Start = (
		GameplayNetAuthority.authority_start(spec_policy) if net.is_authority()
		else GameplayNetAuthority.client_start(spec_policy)
	)
	if decided == GameplayNetAuthority.Start.RUN_NOW or decided == GameplayNetAuthority.Start.REFUSED:
		return decided

	var id: GameplayNetEntityId = net.registry.entity_for(asc)
	var named: GameplayNetDefinitionId = net.registry.register_definition(definition)
	if not id.is_valid() or not named.is_valid():
		return GameplayNetAuthority.Start.REFUSED

	var asking: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.ACTIVATION_REQUEST, id
	)
	asking.definition = named
	# An ability that replicates its input directly does not ask to be
	# activated. The press crosses instead and the authority decides what
	# activating it means, which is the only arrangement in which letting go
	# can end the run the press started.
	if GameplayNetAbilityPolicy.replicates_input_directly(definition):
		net.requests.press(asc, id, definition)
		return decided
	# A request carries a key whichever way it was started. The predicting
	# client needs it to unwind by; the waiting one needs it because the
	# answer has to name which ask it is answering, and a client with two in
	# flight cannot tell them apart otherwise.
	asking.prediction_key = net.journal.next_key(net.peer)
	# A guess this machine is about to act on gets its window opened here, so
	# that a game predicting under it records what it did without first
	# having to ask which guess it was. Whichever answer arrives closes it.
	#
	# One at a time: a second predicted activation while the first is still
	# in flight is refused a window and names its own key on each operation
	# instead, which is the same thing said the longer way.
	if decided == GameplayNetAuthority.Start.PREDICT_AND_ASK:
		net.journal.open_window(asking.prediction_key)
	net.publish(asking)
	return decided
#endregion


#region What arrives
## An activation request, judged and answered - the request kind's own
## handler, called from `GameplayNetworkRuntime._act_on`.
func honour_request(
	message: GameplayNetMessage, from_peer: int = GameplayNetRegistry.NO_PEER
) -> bool:
	var definition: Resource = net.registry.definition_for(message.definition)
	if definition == null:
		net._refuse(message, GameplayNetworkRuntime.REASON_UNKNOWN_DEFINITION)
		return false

	var refusal: StringName = _why_not(message, from_peer, definition)
	if refusal != &"":
		net._refuse(message, refusal)
		answer(GameplayNetMessage.Kind.ACTIVATION_REJECT, message)
		return false
	var assigned: GameplayNetActivationId = answer(GameplayNetMessage.Kind.ACTIVATION_CONFIRM, message)
	net.activation_requested.emit(message.entity, definition, message.prediction_key, assigned)
	return true


## Why this request will not be honoured, or nothing when it will.
##
## Both refusals are answered rather than dropped in silence. The ordinary
## reason a well-formed request is refused is that something moved between
## the asking and the arrival - a character changed hands, a grant was
## revoked - and the client that asked is holding a guess it needs to unwind.
## Saying nothing would leave it holding that guess for ever.
##
## Checked in this order because a key naming somebody else has to fail before
## either side is asked whether it owns anything: with the key trusted first,
## a peer that names a stranger's key on its own request answers the ownership
## question about the stranger rather than about itself, and a stranger who
## really does own the entity would have that request accepted on the strength
## of a claim the transport never actually heard from them.
func _why_not(
	message: GameplayNetMessage, from_peer: int, definition: Resource
) -> StringName:
	if (
		from_peer != GameplayNetRegistry.NO_PEER
		and message.is_predicted()
		and message.prediction_key.peer != from_peer
	):
		return GameplayNetworkRuntime.REASON_PEER_MISMATCH
	# The transport's own word for who asked, when there is one. Falling back
	# to what the message claims is what every direct call in this addon's own
	# suite does - there is no transport in that path to have an opinion - and
	# it is exactly the claim the check above has already made sure agrees
	# with reality whenever there is a transport to check it against.
	var asking: int = (
		from_peer if from_peer != GameplayNetRegistry.NO_PEER
		else message.prediction_key.peer if message.is_predicted()
		else net.registry.owner_of(message.entity)
	)
	if not net.registry.is_owned_by(message.entity, asking):
		return GameplayNetworkRuntime.REASON_NOT_OWNED
	var where: GameplayAbility.NetExecutionPolicy = (
		GameplayNetAbilityPolicy.execution_of(definition)
	)
	if not GameplayNetAuthority.honours_request(true, where):
		return GameplayNetworkRuntime.REASON_POLICY
	# And what this ability accepts from somebody else, which is a different
	# question from where it runs.
	if not GameplayNetAuthority.accepts_remote_start(
		GameplayNetAbilityPolicy.security_of(definition)
	):
		return GameplayNetworkRuntime.REASON_POLICY
	return &""


## Say yes or no to a request, naming the run and the guess it answers.
## Answers with the run it just named, so a caller reacting to
## `activation_requested` can claim a target provider under the same id
## `honour_target_data` will later look an aim up by - AUD-09.
##
## The key is echoed rather than looked up: the machine that asked is the
## one holding the journal, and an answer that did not name the guess would
## leave a client with two casts in flight unwinding the wrong one.
func answer(kind: GameplayNetMessage.Kind, asked: GameplayNetMessage) -> GameplayNetActivationId:
	var id: GameplayNetEntityId = asked.entity
	_runs[id.value] = _runs.get(id.value, 0) + 1
	var made: GameplayNetMessage = GameplayNetMessage.of(kind, id)
	made.activation = GameplayNetActivationId.of(id, _runs[id.value])
	made.definition = asked.definition
	made.prediction_key = asked.prediction_key
	net.publish(made)
	return made.activation
#endregion
