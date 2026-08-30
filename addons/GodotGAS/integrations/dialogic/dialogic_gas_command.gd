## One instruction a dialogue asked the ability system to carry out.
##
## A typed value rather than the Dictionary it arrived as. Dialogic hands its
## listeners an untyped argument, and that argument stops at the parser: nothing
## downstream of it ever reads a key by name, so a schema change breaks one file
## loudly instead of several quietly.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name DialogicGasCommand extends RefCounted


## What the dialogue asked for. Closed, so a message naming something outside
## this list is refused rather than half-understood.
enum Type {
	SEND_EVENT,
	ADD_TAG,
	REMOVE_TAG,
}

var type: Type = Type.SEND_EVENT

## Which ability system this was addressed to. A scene can have several bridges
## listening to the same dialogue bus, and each answers only for its own.
var channel: StringName = &""

var tag: StringName = &""

## Carried on a SEND_EVENT and ignored by the tag commands.
var magnitude: float = 0.0
