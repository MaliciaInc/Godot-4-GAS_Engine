## The sample, run as the authority, in a process of its own.
##
##     godot --headless --path . -s res://examples/action_sample/network/server_main.gd \
##         -- --server --port=47921 --automation --out=user://server.json
##
## What it is for: everything else about this engine's networking is checked
## with two runtimes in one process, which is a fine way to check the rules and
## no way at all to check that bytes cross. Here the two halves are two
## operating-system processes with an ENet connection between them, and the only
## thing they share is the wire.
##
## The authority answers; it does not decide. A request arrives, the rules say
## yes or no, and when they say yes this file runs the ability - because what
## activating means belongs to the game and not to the runtime that carried the
## question.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
extends SceneTree

## How often the client is told what changed. Ten a second, which is a rate a
## game would pick rather than the frame rate, and is the reason deltas exist.
const READING_INTERVAL: float = 0.1

## Ticks to keep going after the last reading is sent, so it reaches the wire
## before this process stops existing.
const GRACE_TICKS: int = 20

var session: SampleNetSession = null
var options: SampleNetOptions = null

var _client_peer: int = GameplayNetRegistry.NO_PEER
var _settled: bool = false
var _grace: int = 0
var _since_reading: float = 0.0


## Nothing but the arguments, because there is no tree yet.
##
## A SceneTree script is running before its own tree is: a node added here is a
## node whose `_ready` has not happened, and an ability system component that
## was never in a tree is one whose runtimes are still null. So the standing
## happens on the first tick, which is the first moment there is one.
func _initialize() -> void:
	options = SampleNetOptions.read()


## Drive the conversation: readings out, and an ending when there is one.
func _process(delta: float) -> bool:
	if session == null:
		return _stand()
	if _grace > 0:
		_grace -= 1
		return _grace == 0

	if session.out_of_patience(delta):
		_stop("nothing finished within %.0f seconds" % SampleNetSession.PATIENCE_SECONDS)
		return false

	if _client_peer == GameplayNetRegistry.NO_PEER:
		return false

	_since_reading += delta
	if _since_reading >= READING_INTERVAL:
		_since_reading = 0.0
		session.network.delta_for(GameplayNetEntityId.of(SampleNetSession.HERO), _client_peer)
	return false


func _finalize() -> void:
	if session != null:
		session.close()


## Build the world and start listening. Answers whether to stop already.
func _stand() -> bool:
	session = SampleNetSession.standing(self, GameplayNetAuthority.Role.AUTHORITY)
	if not options.is_server:
		_stop("this is the authority's entry point; it was asked for %s" % options.spelling())
		return false
	if not session.open(true, "", options.port):
		_stop(session.fault)
		return false

	session.say("listening on port %d" % options.port)
	session.api.peer_connected.connect(_on_peer_connected)
	session.api.peer_disconnected.connect(_on_peer_disconnected)
	session.world.hero.asc.gameplay_event_received.connect(_on_event)
	session.network.activation_requested.connect(_on_request_accepted)
	session.complain()
	return false


#region What the client does, and what this machine does about it
## Somebody connected: give them the character and everything about it.
##
## The order matters and is the late-joiner order. The entity is bound first,
## because a message about an entity this machine has not registered is refused
## and the refusal reads like the thing that was being tested. Then the grants,
## so the client knows which abilities exist before it is told what is running.
## Then one whole snapshot, because a delta against nothing would apply half a
## character.
func _on_peer_connected(id: int) -> void:
	_client_peer = id
	session.attach(id)

	var entity: GameplayNetEntityId = GameplayNetEntityId.of(SampleNetSession.HERO)
	for spec: GameplayAbilitySpec in session.world.hero.asc.get_ability_specs():
		session.network.grant(entity, spec.definition.ability_scene)
	session.say("granted %d abilities to peer %d" % [
		session.world.hero.asc.get_ability_specs().size(), id
	])

	session.network.snapshot_for(entity, id)
	session.say("sent the opening snapshot")


## A request the rules accepted. Running it is this file's business.
##
## Aimed at the first dummy for a strike, and left to its own aiming for the
## slam - which is the whole point of the slam being here: the authority starts
## a provider, claims it under the run it just named, and the client's aim
## arrives as target data addressed to that same run (AUD-09) - never to
## "whichever provider happens to be waiting", which stops being one answer
## the moment a second ability is aiming at once.
func _on_request_accepted(
	_entity: GameplayNetEntityId,
	definition: Resource,
	_key: GameplayPredictionKey,
	activation: GameplayNetActivationId
) -> void:
	var tag: StringName = _tag_of(definition)
	session.say("accepted a request for %s" % tag)
	match tag:
		SampleBasicAttack.TAG:
			session.world.hero.strike(session.world.dummies[0])
		SampleGroundSlam.TAG:
			session.world.hero.aim_slam()
			session.claim_current_aim(activation)
		_:
			# Nothing else in this sample is a client's to ask for, and the rules
			# refused it before this was ever called.
			pass


## The client says it has nothing left to do.
##
## One last whole snapshot rather than a delta, so what the two processes
## compare is the same shape on both sides and neither is comparing a reading
## that only says what changed.
func _on_event(event: GameplayEventData) -> void:
	if event.event_tag != SampleNetSession.SETTLED or _settled:
		return
	_settled = true
	var entity: GameplayNetEntityId = GameplayNetEntityId.of(SampleNetSession.HERO)
	session.network.snapshot_for(entity, _client_peer)
	session.say("the client settled; sent the closing snapshot")
	_finish()


## The client left without saying so, which is a failure rather than an ending.
func _on_peer_disconnected(id: int) -> void:
	if _settled:
		return
	_stop("peer %d left before it settled" % id)
#endregion


#region Ending
## What this process believes the character to be, as it would send it.
func _converged_on() -> String:
	return SampleNetSession.fingerprint(
		GameplayNetReplication.snapshot_of(
			session.world.hero.asc,
			session.network.registry,
			session.network.replication_mode,
			true
		)
	)


func _finish() -> void:
	session.report(options.out, _converged_on())
	_grace = GRACE_TICKS


func _stop(why: String) -> void:
	session.stopping(why)
	session.report(options.out, _converged_on())
	quit(1)


func _tag_of(definition: Resource) -> StringName:
	for spec: GameplayAbilitySpec in session.world.hero.asc.get_ability_specs():
		if spec.definition.ability_scene == definition:
			return spec.definition.ability_tags[0] if not spec.definition.ability_tags.is_empty() else &""
	return &""
#endregion
