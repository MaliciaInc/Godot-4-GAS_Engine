## Which control an argument wants, and why.
##
## A question about a field, answered without building anything. That is the
## whole reason it lives apart from the row that does the building: the answer
## can be asked anywhere - in a test, in a panel, on a machine where the
## editor-only controls cannot be constructed at all - and asking it never has
## the side effect of putting a widget on screen.
##
## The decision is made from the type AND from what the field currently holds,
## never from the type alone. A `float` argument can hold `pick.strength`, and a
## spinner over that is a control which cannot show what is written and destroys
## it the moment it is touched.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerValueShape extends RefCounted

## What a field is edited with.
enum Kind { RAW, BOOL, ENUM, NUMBER, TEXT, VECTOR, COLOUR, RESOURCE, WIRED }

## How many components each vector type is written with. One table rather than a
## chain of comparisons, and the same table the row builds its boxes from, so a
## four-component vector cannot be decided one way and built the other.
const SIZES: Dictionary[StringName, int] = {
	ComposerTypes.VECTOR2: 2,
	ComposerTypes.VECTOR2I: 2,
	ComposerTypes.VECTOR3: 3,
	ComposerTypes.VECTOR3I: 3,
	ComposerTypes.VECTOR4: 4,
	ComposerTypes.VECTOR4I: 4,
}


## Which control this field wants.
static func of(field: ComposerNode.Field) -> ComposerValueShape.Kind:
	if field == null:
		return Kind.RAW
	# A wired field is edited by the wire. Putting a live control on it would
	# give somebody two ways to set one argument, one of which silently breaks
	# the cable they can see attached to it.
	if field.source == ComposerNode.ValueSource.WIRED:
		return Kind.WIRED
	if ComposerTypes.inherits(field.type_name, &"Resource") and _resource_shaped(field):
		return Kind.RESOURCE
	if not ComposerValueCodec.is_literal(field):
		return Kind.RAW
	if field.type_name == ComposerTypes.BOOL:
		return Kind.BOOL
	# Before a number, because an enum *is* an int and a spinner over one offers
	# every value between the ones that mean something. Only when the file holds
	# a number the hint actually lists: a symbol stays text, or opening the row
	# would turn somebody's `SomeEnum.RUN` into whichever option came first.
	if ComposerEnumHint.supports(field):
		return Kind.ENUM
	if field.type_name == ComposerTypes.INT or field.type_name == ComposerTypes.FLOAT:
		return Kind.NUMBER
	if SIZES.has(field.type_name):
		return Kind.VECTOR
	if field.type_name == ComposerTypes.COLOR:
		return Kind.COLOUR
	return Kind.TEXT


## Whether a Resource argument holds something a picker could show: nothing, or
## one saved file. Anything else - a constructed resource, a call - is somebody
## writing code, and a picker would offer to replace it with a file.
static func _resource_shaped(field: ComposerNode.Field) -> bool:
	var written: String = field.display.strip_edges()
	if written == ComposerTypes.NOTHING:
		return true
	return (
		written.begins_with(ComposerValueCodec.PRELOAD_OPEN)
		and written.ends_with(ComposerValueCodec.PRELOAD_SHUT)
	)
