## What one machine says to another about the ability system.
##
## One envelope with named fields rather than a call per thing to say. Every
## message is about an entity, most are about a definition or a run of one, and
## the predicted ones carry the guess they belong to - so those are fields, and
## a reader can tell what a message is about without knowing which RPC it
## arrived on.
##
## The engine never reads `payload`. Everything the ability system itself needs
## is a named field above it; the payload is where a game's own data travels,
## and keeping the two apart is what stops the engine growing a second, untyped
## API made of dictionary keys.
##
## No `get_instance_id()` reaches this class, and no local handle is converted
## into one of these ids. A handle names an object in one process; these name
## the same thing on both. Mapping between them is the network runtime's job and
## it is a table, not a cast.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayNetMessage extends RefCounted

## What this message is for.
##
## Closed, because a receiver branching on an open set is a receiver with a
## default case, and the default case is where an unhandled message goes to be
## quietly ignored.
enum Kind {
	GRANT,
	REVOKE,
	ACTIVATION_REQUEST,
	ACTIVATION_CONFIRM,
	ACTIVATION_REJECT,
	STATE_SNAPSHOT,
	STATE_DELTA,
	CUE,

	## What a client aimed at, on its way to the authority to be checked.
	TARGET_DATA,

	## The generic yes and no: a player confirming or calling off whatever is
	## currently waiting on them.
	GENERIC_CONFIRM,
	GENERIC_CANCEL,

	## An event, in the one shape F6.1.3 already gave events on a wire.
	GAMEPLAY_EVENT,

	## An input, for the abilities whose policy says the input itself crosses
	## rather than the activation it would cause.
	INPUT_PRESSED,
	INPUT_RELEASED,

	## Several of the above, applied together or not at all.
	BATCH,
}

## Where a target aim travels in the payload.
##
## A key rather than a field of its own: an aim is a shape the targeting layer
## owns, and a message that had a typed field for it would be the networking
## layer holding an opinion about what an aim is made of.
const TARGET_DATA_KEY: String = "payload.target_data"

## Which input slot an INPUT_PRESSED or INPUT_RELEASED is about.
const INPUT_KEY: String = "payload.input"

## The messages a BATCH carries, each in its own wire form, and whether the
## batch stands or falls together.
const BATCH_KEY: String = "payload.messages"
const ATOMIC_KEY: String = "payload.atomic"

## The event an GAMEPLAY_EVENT carries, in GameplayEventWire's own shape.
const EVENT_KEY: String = "payload.event"

var kind: GameplayNetMessage.Kind = Kind.STATE_DELTA

## Who it is about. Every message has one: there is nothing to say about the
## ability system that is not about some entity's.
var entity: GameplayNetEntityId = null

## Which definition, for the messages that name one - a grant, a revoke, a
## request to activate. Null on the ones that do not.
var definition: GameplayNetDefinitionId = null

## Which run, for the messages that are about one.
var activation: GameplayNetActivationId = null

## The guess this belongs to, on a message that is part of one. Null on
## anything the server said on its own account.
var prediction_key: GameplayPredictionKey = null

## The state a snapshot or a delta carries. Null on every other kind.
var state: GameplayNetState = null

## Which reading of an entity's state this is, counted by the authority.
##
## State is the one kind where arriving twice and arriving late are
## different problems. Twice is harmless, because a delta carries values
## rather than increments and writing the same value again changes nothing.
## Late is not: an older reading applied after a newer one puts a character
## back the way it was half a second ago, and nothing afterwards corrects it
## until the next change to that same attribute. So a reading says which one
## it is, and a receiver ignores anything it has already moved past.
var sequence: int = 0

## What `to_peer` says when a message is for everybody, which is Godot's own
## spelling of it and is why it is zero rather than something this addon chose.
const EVERYBODY: int = 0

## Which peer this is for, or EVERYBODY.
##
## Never written to the wire, and that is the whole of what it is: a routing
## hint for the machine holding the message, not something a receiver is told.
##
## It exists because a state reading is computed for one recipient. What a peer
## may be told depends on whether it owns the entity - under MIXED the owner
## gets the running effects and nobody else does, and only the owner is told
## which of its abilities are running - so a reading built for one peer and
## broadcast to all of them hands everybody the owner's answer. The filtering
## was there and the sending ignored it.
var to_peer: int = EVERYBODY

## The game's own data. Never read by this addon.
var payload: Dictionary = {}


static func of(message_kind: GameplayNetMessage.Kind, about: GameplayNetEntityId) -> GameplayNetMessage:
	var made: GameplayNetMessage = GameplayNetMessage.new()
	made.kind = message_kind
	made.entity = about
	return made


## Whether this message names somebody to be about.
##
## A message with no entity is one the receiver cannot act on and must not
## guess about: acting on "whoever this probably meant" is how a client's
## request becomes another client's cooldown.
func is_addressed() -> bool:
	return entity != null and entity.is_valid()


## Whether this is a predicted message rather than one the authority made on
## its own account.
func is_predicted() -> bool:
	return prediction_key != null and prediction_key.is_valid()


## Whether this message is a reading of an entity's state rather than
## something that happened to it.
func is_state() -> bool:
	return kind == Kind.STATE_SNAPSHOT or kind == Kind.STATE_DELTA


## Whether this message carries everything its kind is required to carry.
##
## Checked at the boundary rather than at every reader. A confirm without a run
## to confirm, or a grant without a definition to grant, is a message that will
## be acted on with a null in the middle of it - and the reader that finds out
## is the one furthest from where it went wrong.
func is_complete() -> bool:
	if not is_addressed():
		return false
	match kind:
		Kind.GRANT, Kind.REVOKE:
			return definition != null and definition.is_valid()
		Kind.ACTIVATION_REQUEST:
			# A key is what says whose guess this is - AUD-06. Every request
			# `GameplayNetActivationRuntime.start()` ever sends carries one,
			# whichever way the ability was started, so requiring it here
			# writes down a rule production code already keeps rather than
			# relying on it staying true because nothing has tested otherwise.
			return (
				definition != null and definition.is_valid()
				and prediction_key != null and prediction_key.is_valid()
			)
		Kind.ACTIVATION_CONFIRM, Kind.ACTIVATION_REJECT:
			# Both halves of what an answer is about: which run, and which
			# guess it is the answer to. `GameplayNetActivationRuntime.answer()`
			# always echoes the request's own key back, so an answer missing
			# one names a run without saying which of a client's guesses it
			# was ever an answer to.
			return (
				activation != null and activation.is_valid()
				and prediction_key != null and prediction_key.is_valid()
			)
		Kind.STATE_SNAPSHOT, Kind.STATE_DELTA:
			return state != null
		Kind.TARGET_DATA:
			# An aim with nothing in it is a caller that forgot to aim, and
			# acting on it would be the authority validating an empty claim.
			return payload.has(TARGET_DATA_KEY)
		Kind.GAMEPLAY_EVENT:
			return payload.has(EVENT_KEY)
		Kind.INPUT_PRESSED, Kind.INPUT_RELEASED:
			# By definition rather than by the client's own handle: a handle is
			# a number one machine made up, and resolving a request by it is
			# resolving it by something the authority never agreed to.
			return definition != null and definition.is_valid() and payload.has(INPUT_KEY)
		Kind.BATCH:
			return payload.has(BATCH_KEY)
		_:
			return true
