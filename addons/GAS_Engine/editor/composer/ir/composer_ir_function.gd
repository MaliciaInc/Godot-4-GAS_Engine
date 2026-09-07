## One function of a script, cut into what it is made of.
##
## The Composer draws one of these - `_activate_ability()` - and knows about the
## rest so that it can leave them alone with confidence rather than by never
## having looked. A helper method is not an obstacle to drawing the entry point;
## it was only ever treated as one because the reader had no idea a file had
## more than one function in it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerIRFunction extends RefCounted

## What it is called, without `func` and without its arguments.
var declared_name: StringName = &""

## The line the signature is on.
var signature_line: int = ComposerSpan.NO_LINE

## The body: the first line under the signature through the last line of it.
## Invalid when the function has no body worth speaking of.
var body: ComposerSpan = ComposerSpan.new()

## What the signature says it returns, or empty when it says nothing.
var returns: StringName = &""

## Everything in the body, in the order it is written.
var events: Array[ComposerIREvent] = []

## The loops in it, which are also opaque events. Kept as their own list because
## "can this be drawn" and "where does this stop being drawable" are two
## questions, and answering the second by filtering the first means every caller
## re-derives what a loop looks like.
var loops: Array[ComposerIRLoop] = []

## Every point at which it suspends.
var async_exits: Array[ComposerIRAsyncExit] = []


func is_entry_point() -> bool:
	return declared_name == StringName(ComposerSubset.ENTRY_POINT)


## The events this tool cannot draw as themselves.
func opaque_events() -> Array[ComposerIREvent]:
	var found: Array[ComposerIREvent] = []
	for event: ComposerIREvent in events:
		if event.is_opaque():
			found.append(event)
	return found


## Whether every event in it is one the tool understands.
##
## Not the same question as whether it can be opened. A body with one opaque
## region in it is drawn, edited and saved; this only says whether anything in
## it had to be left alone.
func is_fully_representable() -> bool:
	return opaque_events().is_empty()


## Whether it can suspend at all, which is what makes an ability able to outlive
## its own activation.
func suspends() -> bool:
	return not async_exits.is_empty()
