## What both halves of the two-process sample stand on.
##
## A character, an ability system, a network runtime over Godot's own
## SceneMultiplayer, and a way to say what state this process ended in. The
## server and the client differ in what they do with those, not in what they
## are, and writing the standing twice is how the two halves come to disagree
## about which entity is which.
##
## Nothing here is test scaffolding. It is the shortest honest answer to "how do
## I put this engine on a network", and the two mains beside it are the shortest
## honest answer to "and then what do I do with it".
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleNetSession extends RefCounted

## The entity id both processes use for the hero.
##
## Fixed rather than negotiated, because this sample has one character and a
## negotiation would be the part of a real game that has nothing to do with the
## ability system.
const HERO: int = 1

## What the client sends when it has nothing left to do, and what the
## authority waits for before its closing snapshot. One name, on the class
## both halves already share: two spellings of an agreement is an agreement
## that can be edited on one side.
const SETTLED: StringName = &"Event.Sample.Settled"

## Where the sample listens, unless a caller says otherwise. High enough to be
## nobody's service and low enough to be nobody's ephemeral port.
const DEFAULT_PORT: int = 47921

## How long either half waits for the other before giving up and saying so.
##
## A deadline rather than none: a harness whose failure mode is "both processes
## are still running" is a harness that hangs a machine rather than reporting a
## broken handshake.
const PATIENCE_SECONDS: float = 30.0

var tree: SceneTree = null
var peer: ENetMultiplayerPeer = null
var world: SampleWorld = null
var network: GameplayNetworkRuntime = null

## Godot's own multiplayer, held typed. A SceneTree answers `get_multiplayer()`
## as a MultiplayerAPI, and every caller casting it back is every caller
## having an opinion about which kind this addon needs.
var api: SceneMultiplayer = null
var transport: GameplayNetTransportMultiplayer = null

## What this process has done, in order, for the receipt.
var steps: PackedStringArray = PackedStringArray()

## Why it stopped, when it stopped badly.
var fault: String = ""

var _elapsed: float = 0.0


## Build the sample world and the runtime over it, in whichever role.
##
## The world rather than a bare component, because the point of running the
## sample over a wire is that it is the sample: the same hero, the same three
## abilities, the same cues bound into the same manager.
static func standing(
	scene_tree: SceneTree, role: GameplayNetAuthority.Role
) -> SampleNetSession:
	var session: SampleNetSession = SampleNetSession.new()
	session.tree = scene_tree
	session.world = SampleWorld.new()
	scene_tree.root.add_child(session.world)
	# Built here rather than waiting for `_ready`: a process that is setting
	# itself up before the first frame has no frame for `_ready` to have
	# happened in, and the door exists for exactly this caller.
	session.world.build()

	session.network = GameplayNetworkRuntime.new()
	session.network.role = role
	session.transport = GameplayNetTransportMultiplayer.new()
	return session


## Start listening, or start connecting. Answers whether the peer came up.
func open(as_server: bool, address: String, port: int) -> bool:
	peer = ENetMultiplayerPeer.new()
	var started: Error = (
		peer.create_server(port, 1) if as_server else peer.create_client(address, port)
	)
	if started != OK:
		fault = "the peer would not start: error %d" % started
		return false

	api = tree.get_multiplayer() as SceneMultiplayer
	if api == null:
		fault = "this tree has no SceneMultiplayer"
		return false
	api.multiplayer_peer = peer
	transport.bind(api)
	network.set_transport(transport)
	network.peer = api.get_unique_id()
	return true


## Bind this process's hero to the shared entity id, and name its abilities.
##
## Both processes do this, with the same id and the same owning peer, and both
## register the same definitions - which is the other half of agreeing about a
## character. A machine told about a grant it cannot name refuses the message,
## and the refusal reads like a dropped packet.
func attach(owner_peer: int) -> void:
	network.attach(world.hero.asc, GameplayNetEntityId.of(HERO), owner_peer)
	var named: int = 0
	for spec: GameplayAbilitySpec in world.hero.asc.get_ability_specs():
		if network.registry.register_definition(spec.definition.ability_scene).is_valid():
			named += 1
	say("attached the hero as entity %d owned by peer %d, naming %d abilities" % [
		HERO, owner_peer, named
	])


## Give up, and say why. The caller writes the receipt and quits.
##
## Here rather than in each half because the two mains stop for different
## reasons and in the same words, and a sentence written twice is a sentence
## a reader has to check is the same one.
func stopping(why: String) -> void:
	fault = why
	say("stopping: %s" % why)


## Say out loud what this machine refused and why.
##
## A sample that dropped messages in silence would be a sample somebody debugs
## with a packet capture. Every refusal this addon makes has a reason, and the
## reason is the first thing worth printing.
func complain() -> void:
	network.message_refused.connect(
		func(message: GameplayNetMessage, reason: StringName) -> void:
			say("refused a %s: %s" % [GameplayNetMessage.Kind.keys()[message.kind], reason])
	)


## The ability scene behind one of the hero's grants, by tag.
##
## By tag because that is what this sample calls its abilities, and the scene
## rather than the spec because a network runtime names definitions.
func definition_tagged(tag: StringName) -> Resource:
	for spec: GameplayAbilitySpec in world.hero.asc.get_ability_specs():
		if spec.definition != null and spec.definition.ability_tags.has(tag):
			return spec.definition.ability_scene
	return null


## Write down that something happened, in the order it happened.
func say(what: String) -> void:
	steps.append(what)
	print("[%s] %s" % [_role_name(), what])


## Whether the deadline has passed, counted from the first tick.
func out_of_patience(delta: float) -> bool:
	_elapsed += delta
	return _elapsed > PATIENCE_SECONDS


## What this process believes the shared character's state to be, canonically.
##
## The reading rather than the component, because a reading is what crosses and
## what convergence is about: the authority hashes what it would send, the
## client hashes what it last received, and the two matching is the two
## processes agreeing about a character.
##
## Sorted, and without any clock in it. Two processes started a second apart
## disagree about how much time is left on a cooldown and agree about
## everything that matters, and a hash that included the clock would report the
## second-hand rather than the state.
static func fingerprint(state: GameplayNetState) -> String:
	if state == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for name: StringName in _sorted(state.attributes.keys()):
		parts.append("attr %s=%.3f" % [name, state.attributes[name]])
	for name: StringName in _sorted(state.current_attributes.keys()):
		parts.append("current %s=%.3f" % [name, state.current_attributes[name]])
	for tag: StringName in _sorted(state.tags.keys()):
		parts.append("tag %s=%d" % [tag, state.tags[tag]])
	for granted: int in _sorted_ints(state.abilities):
		parts.append("ability %d" % granted)
	for running: int in _sorted_ints(state.running_abilities):
		parts.append("running %d" % running)
	for cue: StringName in _sorted(state.cues):
		parts.append("cue %s" % cue)
	for effect: GameplayNetEffectState in _by_id(state.effects):
		parts.append(
			"effect %d x%d %s" % [effect.id, effect.stack_count, effect.inhibited]
		)
	return "\n".join(parts)


static func _sorted(names: Array) -> Array[StringName]:
	var listed: Array[StringName] = []
	for one: Variant in names:
		listed.append(one)
	listed.sort()
	return listed


static func _sorted_ints(values: Array[int]) -> Array[int]:
	var listed: Array[int] = values.duplicate()
	listed.sort()
	return listed


static func _by_id(effects: Array[GameplayNetEffectState]) -> Array[GameplayNetEffectState]:
	var listed: Array[GameplayNetEffectState] = effects.duplicate()
	listed.sort_custom(
		func(one: GameplayNetEffectState, other: GameplayNetEffectState) -> bool:
			return one.id < other.id
	)
	return listed


## Write what this process ended with, for the harness to compare.
##
## A file rather than stdout, because two processes interleaving their output is
## exactly the kind of thing that reads as a passing run until somebody looks.
func report(into: String, converged_on: String) -> void:
	var receipt: Dictionary = {
		"role": _role_name(),
		"fault": fault,
		"steps": steps,
		"state": converged_on,
	}
	var file: FileAccess = FileAccess.open(into, FileAccess.WRITE)
	if file == null:
		push_error("SampleNetSession: cannot write %s" % into)
		return
	file.store_string(JSON.stringify(receipt, "\t"))
	file.close()


## Let go of everything, in the order that leaves nothing holding anything.
func close() -> void:
	network.dispose()
	transport.unbind()
	if peer != null:
		peer.close()
	if world != null and is_instance_valid(world):
		world.queue_free()


func _role_name() -> String:
	return "server" if network.is_authority() else "client"
