## What an `@export_enum` argument is allowed to hold, read off the engine's hint.
##
## Reflection describes an enum parameter as an int with a hint string listing
## its names, and that string is the only place the names exist at runtime: the
## enum's own identifier is not preserved, so a control here can offer the words
## a person wrote and must write back the number they stand for. Writing
## `SomeEnum.RUN` would be inventing an owner nobody said.
##
## A token this cannot read stops the whole list. Half a parse is a dropdown
## missing an option, which is a value somebody can no longer choose and cannot
## see they have lost - so an unreadable hint is answered with nothing at all and
## the field falls back to being typed into.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerEnumHint extends RefCounted

const SEPARATOR: String = ","
const ASSIGNMENT: String = ":"


## One choice: the word a person reads, and the number the file holds.
class Option extends RefCounted:
	var label: String = ""
	var value: int = 0

	static func of(label: String, value: int) -> Option:
		var made: Option = Option.new()
		made.label = label
		made.value = value
		return made


## The choices a hint string lists, or nothing when it lists something this
## cannot read.
##
## `Idle,Walk,Run` counts from zero. `Idle:0,Walk:2,Run:7` says its own numbers.
## Mixed, an implicit value carries on from the last explicit one - which is what
## GDScript itself does, so a dropdown built from this offers the same numbers
## the language would.
static func parse(hint_string: String) -> Array[Option]:
	var found: Array[Option] = []
	if hint_string.strip_edges().is_empty():
		return found

	var next: int = 0
	for token: String in hint_string.split(SEPARATOR):
		var said: String = token.strip_edges()
		if said.is_empty():
			return []
		var mark: int = said.find(ASSIGNMENT)
		if mark < 0:
			if not _is_a_name(said):
				return []
			found.append(Option.of(said, next))
			next += 1
			continue

		var label: String = said.left(mark).strip_edges()
		var written: String = said.substr(mark + 1).strip_edges()
		if not _is_a_name(label) or not written.is_valid_int():
			return []
		found.append(Option.of(label, written.to_int()))
		next = found[found.size() - 1].value + 1
	return found


## Whether this field is one a dropdown can serve.
##
## Three things at once: the engine says it is an enum, the hint reads, and what
## the file holds is one of the numbers offered. The last is what keeps
## `SomeEnum.RUN` out of a dropdown: it is a symbol, this cannot know which
## number it stands for, and turning it into one would rewrite a person's code
## into a magic number the moment they touched the row.
static func supports(field: ComposerNode.Field) -> bool:
	if field == null or field.variant_type != TYPE_INT:
		return false
	if field.hint != PROPERTY_HINT_ENUM:
		return false
	var written: String = field.display.strip_edges()
	if not written.is_valid_int():
		return false
	return value_index(parse(field.hint_string), written.to_int()) >= 0


## Which choice holds that number, or -1 when none does.
static func value_index(options: Array[Option], value: int) -> int:
	for index: int in options.size():
		if options[index].value == value:
			return index
	return -1


## Whether that is a name and not something that only looks like one.
##
## A label with a space or a bracket in it is a hint this did not understand, and
## the rule is the same as everywhere else here: say nothing rather than guess.
static func _is_a_name(text: String) -> bool:
	return text.is_valid_identifier()
