## The words the running game and the editor use to talk about what happened.
##
## Two processes have to agree on a vocabulary, and the only way that agreement
## survives is if it is written once. A key spelled in the game and spelled
## again in the debugger is a message that arrives and is silently ignored -
## the worst failure this could have, because a debugger that shows nothing
## looks exactly like a game in which nothing happened.
##
## Declared on the runtime side rather than the editor side, and deliberately:
## the game cannot name anything under `editor/`, so a vocabulary living there
## could only be half shared. The editor may name this, which is the direction
## that is allowed.
##
## Nothing here reaches the debugger by itself. It is names and shapes; the
## sending is `GasDebugChannel`'s and the reading is the editor's.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugMessage extends RefCounted

## What the debugger files these messages under.
##
## The name is derived from the addon's own project-settings name rather than
## spelled again: two spellings of one channel is a game talking to a debugger
## that is not listening, which looks exactly like a game in which nothing
## happened.
const CAPTURE: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME

## The two things the game ever sends: what an entity looks like right now, and
## something that just happened to it.
const SNAPSHOT: String = CAPTURE + ":snapshot"
const TRACE: String = CAPTURE + ":trace"

## Which kind of thing happened.
##
## Each one is a moment somebody debugging an ability asks about: why did it not
## start, when did the effect land, what took the tag off. They are named rather
## than numbered so a log is readable without the editor that produced it.
enum Kind {
	ABILITY_GRANTED,
	ABILITY_ACTIVATED,
	ABILITY_COMMITTED,
	ABILITY_ENDED,
	ABILITY_REFUSED,
	EFFECT_APPLIED,
	EFFECT_REFUSED,
	EFFECT_TICKED,
	EFFECT_REMOVED,
	TAG_COUNT_CHANGED,
	ATTRIBUTE_CHANGED,
	CUE_EXECUTED,
}

## The keys of a trace message.
const KIND: String = "event_kind"
const AT: String = "at"
const ASC_ID: String = "asc_id"
const SUBJECT: String = "subject"
const DETAIL: String = "detail"

## The keys of a snapshot.
const AVATAR: String = "avatar"
const OWNER: String = "owner"
const ATTRIBUTES: String = "attributes"
const TAGS: String = "held_tags"
const ABILITIES: String = "abilities"
const EFFECTS: String = "effects"

## The keys inside one attribute, one tag, one ability, one effect.
const NAME: String = "name"
const BASE: String = "base"
const CURRENT: String = "current"
const COUNT: String = "count"
const FAMILY_COUNT: String = "family_count"
const HANDLE: String = "handle"
const LEVEL: String = "level"
const ACTIVE: String = "active"
const STACKS: String = "stacks"
const SECONDS_LEFT: String = "seconds_left"
const TURNS_LEFT: String = "turns_left"


## The name of a kind, for a log a person reads without an editor.
static func named(kind: GasDebugMessage.Kind) -> StringName:
	return StringName(key_of(Kind.keys(), int(kind)))


## The name of one value of any enum, for the same reason.
##
## `Enum.keys()` is an untyped Array, so indexing it hands back a Variant and
## every caller would have to widen a type to say a word. Out of range answers
## empty rather than throwing: a debugger is the last thing that should fall
## over on a value it did not expect.
static func key_of(keys: Array, value: int) -> String:
	if value < 0 or value >= keys.size():
		return ""
	var named_key: String = keys[value]
	return named_key
