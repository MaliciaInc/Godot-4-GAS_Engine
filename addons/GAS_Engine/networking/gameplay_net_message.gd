## What one machine says to another about the ability system.
##
## One envelope with named fields rather than a call per thing to say. Every
## message is about an entity, most are about a definition or a run of one, and
## the predicted ones carry the guess they belong to - so those are fields, and
## a reader can tell what a message is about without knowing which RPC it
## arrived on.
##
## What a kind carries beyond those is a typed field of its own - an aim, an
## event, an input slot, a batch, a cue - so the codec writes each in the shape
## its serializer knows and a receiver reads a value rather than looking a key up
## in a dictionary somebody else filled. The engine never reads `payload`: that is
## where a game's own data travels, and keeping the two apart is what stops the
## engine growing a second, untyped API made of dictionary keys.
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

	## An event, in the one shape events cross a wire in.
	GAMEPLAY_EVENT,

	## An input, for the abilities whose policy says the input itself crosses
	## rather than the activation it would cause.
	INPUT_PRESSED,
	INPUT_RELEASED,

	## Several of the above, applied together or not at all.
	BATCH,
}

## The slot an input names when the grant was bound to none.
const NO_INPUT: int = -1

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

## Where a TARGET_DATA message's client aimed, in the shape an aim crosses in.
var aim: GameplayNetAim = null

## The event a GAMEPLAY_EVENT carries.
var event: GameplayEventWire = null

## Which input slot an INPUT_PRESSED or INPUT_RELEASED is about.
var input_id: int = NO_INPUT

## The messages a BATCH carries, and whether they stand or fall together.
var batch: GameplayNetBatch = null

## The cue a CUE carries, when it carries one of the ability system's own.
## Null for a cue that is only the game's own payload.
var cue: GameplayCueWire = null

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

## The game's own data. Never read by this addon, and carried as the values it
## holds - see GameplayNetPayloadSerializer for which values those may be.
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
			# The run it is for is required too - AUD-09 - because without it
			# routing an aim can only mean "whichever provider is waiting
			# first", which is a different provider whenever two are. The key
			# is required for the same reason a request's is: it is what
			# `_identified()` checks an aim's claimed sender against, and an
			# aim that carried none would cross that check for free.
			return (
				aim != null
				and activation != null and activation.is_valid()
				and prediction_key != null and prediction_key.is_valid()
			)
		Kind.GAMEPLAY_EVENT:
			return event != null
		Kind.INPUT_PRESSED, Kind.INPUT_RELEASED:
			# By definition rather than by the client's own handle: a handle is
			# a number one machine made up, and resolving a request by it is
			# resolving it by something the authority never agreed to.
			return definition != null and definition.is_valid()
		Kind.BATCH:
			return batch != null
		_:
			return true
