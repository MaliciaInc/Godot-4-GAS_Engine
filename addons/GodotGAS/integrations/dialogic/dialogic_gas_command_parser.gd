## Turn a message from a dialogue into a typed command, or say what was wrong.
##
## This is the only place in the addon that reads an untyped Dictionary sent by
## Dialogic. Everything past it works in typed values, so the day the schema
## changes, one file stops compiling instead of several quietly reading absent
## keys as empty strings.
##
## `Dialogic.signal_event` is a general-purpose bus: a project uses it for its
## own messages, and most of what arrives here was never meant for the ability
## system. That is why "not for us" is its own answer rather than an error. Only
## a message that claimed to be for this bridge and then turned out malformed is
## worth complaining about - complaining about the rest would bury the real
## complaints under everyone else's traffic.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name DialogicGasCommandParser extends RefCounted


enum Error {
	NONE,
	NOT_FOR_BRIDGE,
	MISSING_CHANNEL,
	UNKNOWN_COMMAND,
	INVALID_TAG,
	INVALID_MAGNITUDE,
}


## What one parse produced: a command, or the reason there is none.
##
## The type is spelled out rather than left as `Error`: Godot has a global enum
## by that name, and an unqualified annotation here resolves to the engine's
## rather than this one - which compiles as far as the first assignment.
class Result extends RefCounted:
	var error: DialogicGasCommandParser.Error = DialogicGasCommandParser.Error.NONE
	var command: DialogicGasCommand = null


## The value a message must carry to be addressed to this bridge at all.
const BRIDGE_NAME: String = "ArhaliesGAS"

const BRIDGE_KEY: StringName = &"bridge"
const CHANNEL_KEY: StringName = &"channel"
const COMMAND_KEY: StringName = &"command"
const TAG_KEY: StringName = &"tag"
const MAGNITUDE_KEY: StringName = &"magnitude"

## The whole vocabulary. A name outside it is refused rather than guessed at.
const COMMANDS: Dictionary[String, DialogicGasCommand.Type] = {
	"send_event": DialogicGasCommand.Type.SEND_EVENT,
	"add_tag": DialogicGasCommand.Type.ADD_TAG,
	"remove_tag": DialogicGasCommand.Type.REMOVE_TAG,
}


static func parse(argument: Variant) -> Result:
	var result: Result = Result.new()

	# Anything that is not a dictionary claiming to be ours belongs to somebody
	# else on the same bus, and is not this bridge's business.
	if not argument is Dictionary:
		result.error = Error.NOT_FOR_BRIDGE
		return result
	var message: Dictionary = argument
	if _text(message, BRIDGE_KEY) != BRIDGE_NAME:
		result.error = Error.NOT_FOR_BRIDGE
		return result

	var command: DialogicGasCommand = DialogicGasCommand.new()

	var channel: String = _text(message, CHANNEL_KEY)
	if channel.is_empty():
		result.error = Error.MISSING_CHANNEL
		return result
	command.channel = StringName(channel)

	var named: String = _text(message, COMMAND_KEY)
	if not COMMANDS.has(named):
		result.error = Error.UNKNOWN_COMMAND
		return result
	command.type = COMMANDS[named]

	# Validated against the registry's own grammar, and not repaired. `add_tag`
	# formats a designer's typing before checking it; a message from outside was
	# not typed by a designer, and quietly correcting it would let the sender
	# believe it addressed a tag it never named.
	var tag: String = _text(message, TAG_KEY)
	if not GameplayTagRegistry.is_valid_tag_string(tag):
		result.error = Error.INVALID_TAG
		return result
	command.tag = StringName(tag)

	# Optional, but not free-form: a magnitude that arrived as text would reach
	# an effect as zero and look like a designer's decision.
	var magnitude: Variant = message.get(MAGNITUDE_KEY, 0.0)
	if magnitude is float:
		var exact: float = magnitude
		command.magnitude = exact
	elif magnitude is int:
		var whole: int = magnitude
		command.magnitude = float(whole)
	else:
		result.error = Error.INVALID_MAGNITUDE
		return result

	result.command = command
	return result


## One field of the message, read as text only if it arrived as text.
##
## Not converted. `String(value)` turns anything into something, so a channel
## that arrived as a number would have become the digits of that number and
## quietly matched nobody. Empty is the honest reading, and every caller above
## refuses on it.
static func _text(message: Dictionary, key: StringName) -> String:
	var value: Variant = message.get(key, "")
	if value is String:
		var text: String = value
		return text
	if value is StringName:
		var named: StringName = value
		return String(named)
	return ""
