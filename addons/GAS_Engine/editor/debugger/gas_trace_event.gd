## One thing that happened in the running game, as the editor holds it.
##
## Built from a message rather than declared twice: the vocabulary is
## `GasDebugMessage`, which lives on the runtime side because the game cannot
## name anything under `editor/` and a vocabulary only half shared is a message
## that arrives and is silently ignored.
##
## Held as a value, not drawn. What a panel does with a list of these is a
## panel's business; what this guarantees is that the list says the same thing
## the game said.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasTraceEvent extends RefCounted

## Which kind of thing happened.
var kind: GasDebugMessage.Kind = GasDebugMessage.Kind.ABILITY_ACTIVATED

## Which entity it happened to, by the instance id the game reported.
##
## An id rather than a reference: the object is in another process, and a
## reference to it here would be a reference to nothing.
var asc_id: int = 0

## What it was about - an ability handle, an effect, a tag, an attribute.
var subject: String = ""

## Whatever else is worth saying: the reason it was refused, the two values an
## attribute moved between, how many of a tag there are now.
var detail: String = ""


## The event a message describes, or null when the message describes none.
##
## Null rather than an empty event. A debugger that showed a row for every
## malformed packet would be showing the person its own bugs.
static func from_message(said: Dictionary) -> GasTraceEvent:
	if not said.has(GasDebugMessage.KIND) or not said.has(GasDebugMessage.ASC_ID):
		return null

	var made: GasTraceEvent = GasTraceEvent.new()
	var kind: int = said[GasDebugMessage.KIND]
	if kind < 0 or kind >= GasDebugMessage.Kind.size():
		return null

	made.kind = kind as GasDebugMessage.Kind
	made.asc_id = said[GasDebugMessage.ASC_ID]
	made.subject = said.get(GasDebugMessage.SUBJECT, "")
	made.detail = said.get(GasDebugMessage.DETAIL, "")
	return made


## One line, the way a log reads: `EFFECT_REMOVED burning (EXPIRED)`.
func described() -> String:
	var said: String = "%s %s" % [GasDebugMessage.named(kind), subject]
	return said if detail.is_empty() else "%s (%s)" % [said, detail]
