## What the Composer knows about one operation, said explicitly.
##
## The catalog used to offer every public method of five classes, and argued for
## it: leaving one out would be answering a question - "is this worth drawing?" -
## that belongs to whoever is writing the ability. The argument was right about
## the question and wrong about who had already answered it. `dispose()`,
## `emit_tag_change()` and `cleanup()` are on the palette under that rule, and
## nobody writes those in an ability: they are how the runtime talks to itself.
## Public in GDScript means "another part of the engine calls this", which is a
## different fact from "somebody authors this".
##
## So an operation says so. A method carries `@composer` in its own doc comment,
## beside the code, where it is read by the person changing that method rather
## than in a list somewhere else that stops being true silently. What it takes
## and what it hands back are still read from the engine by reflection, because
## those are facts about the method and restating them is how a catalog comes to
## name a parameter the API stopped having.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerOperation extends RefCounted

## The marker that makes a method an operation. A category may follow it.
const MARK: String = "@composer:"

## An operation that should no longer be reached for, and what to reach for
## instead. Offered all the same - an ability already written on it still has to
## open - and said out loud on the card.
const DEPRECATED_MARK: String = "@composer_deprecated:"

## What the palette calls it, where the method's own name reads badly.
const NAME_MARK: String = "@composer_name:"

const DOC_PREFIX: String = "##"

## Which method, on which script. The same shape the catalog is keyed by.
var id: StringName = &""

## Which part of the palette it appears under.
var category: StringName = &""

## What the palette calls it.
var display_name: String = ""

## The first line of the method's own doc comment.
##
## Read rather than restated: the sentence explaining a method is already
## written above it, and a second one here would be the copy that drifts.
var description: String = ""

## What it takes and what it hands back, by type, read from the engine.
var input_types: Array[StringName] = []
var output_types: Array[StringName] = []

## The outputs that only exist after the ability has waited.
##
## Empty for an ordinary call. A call that hands back a task hands back
## something with a `finished` on it, and what comes out of that is not
## available on the line the call was written on.
var async_outputs: Array[StringName] = []

## What each parameter falls back to when a caller passes nothing, by position.
##
## Read from the signature. A default is not a gap: a call that leaves one out
## has said everything it needed to, and treating the two the same puts a
## warning on every correct statement in a file.
var defaults: Array = []

## Why this should not be reached for any more, or empty while it should.
var deprecated: String = ""


func is_deprecated() -> bool:
	return not deprecated.is_empty()


## Whether the doc comment above a method declares it an operation.
static func is_declared_in(doc_lines: PackedStringArray) -> bool:
	return not _value_of(doc_lines, MARK).is_empty() or _has_bare_mark(doc_lines)


## The category the marker names, or empty when it names none and the catalog
## should work one out from the name.
static func category_in(doc_lines: PackedStringArray) -> StringName:
	return StringName(_value_of(doc_lines, MARK))


static func name_in(doc_lines: PackedStringArray) -> String:
	return _value_of(doc_lines, NAME_MARK)


static func deprecation_in(doc_lines: PackedStringArray) -> String:
	return _value_of(doc_lines, DEPRECATED_MARK)


## The first sentence of the doc comment: everything before the first blank
## doc line, joined, with the markers taken out.
##
## Empty for a method nobody documented, which is a fact about the method rather
## than something to invent a sentence for.
static func description_in(doc_lines: PackedStringArray) -> String:
	var said: PackedStringArray = PackedStringArray()
	for line: String in doc_lines:
		var text: String = _stripped(line)
		if text.is_empty():
			break
		if text.begins_with("@"):
			continue
		said.append(text)
	return " ".join(said)


#region Reading a doc comment
## The doc line with its `##` and its spacing taken off.
static func _stripped(line: String) -> String:
	return line.strip_edges().trim_prefix(DOC_PREFIX).strip_edges()


static func _value_of(doc_lines: PackedStringArray, mark: String) -> String:
	for line: String in doc_lines:
		var text: String = _stripped(line)
		if text.begins_with(mark):
			return text.substr(mark.length()).strip_edges()
	return ""


## `@composer` on its own, with no category after it, which is how a method says
## "offer me, and work out where I go from my name".
static func _has_bare_mark(doc_lines: PackedStringArray) -> bool:
	var bare: String = MARK.trim_suffix(":")
	for line: String in doc_lines:
		if _stripped(line) == bare:
			return true
	return false
#endregion
