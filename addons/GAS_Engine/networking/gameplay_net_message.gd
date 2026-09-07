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
}

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
			return definition != null and definition.is_valid()
		Kind.ACTIVATION_CONFIRM, Kind.ACTIVATION_REJECT:
			return activation != null and activation.is_valid()
		Kind.STATE_SNAPSHOT, Kind.STATE_DELTA:
			return state != null
		_:
			return true
