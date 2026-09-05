## An argument field, as reflection would have described one.
##
## Every test about a control needs the same thing: a field carrying what the
## engine says about an argument - its type, its hint, and what the file holds
## for it. Written out in each of them it was the same seven lines several times,
## and seven lines repeated are seven chances for one of them to describe an
## argument the catalog would never produce.
##
## Nothing here asserts. A fixture that judged would be a second set of rules to
## keep in step with the real ones.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerDeclaredField extends RefCounted


## A field of that type holding that text, with the hint the engine gave it.
##
## `hint` is passed rather than guessed from the string: a range and an enum are
## both described by a comma-separated list, and telling them apart by looking at
## it is exactly the guess this project keeps out of the reader.
static func of(
	type_name: StringName,
	written: String,
	hint: int = PROPERTY_HINT_NONE,
	hint_string: String = "",
	label: String = "Level"
) -> ComposerNode.Field:
	var made: ComposerNode.Field = ComposerNode.Field.new()
	made.label = label
	made.type_name = type_name
	made.display = written
	made.hint = hint
	made.hint_string = hint_string
	# The code the engine would have reported beside the name. Only the two an
	# int can be described by matter here; everything else is named.
	made.variant_type = TYPE_INT if type_name == ComposerTypes.INT else TYPE_NIL
	made.editable = true
	return made
