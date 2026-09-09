## Offers the attribute picker wherever a `GameplayAttributeRef` is authored.
##
## By the property's type rather than by its name: a reference is a reference
## wherever it appears - on a modifier, on a cue binding, on a capture - and a
## plugin matching on names would have to be told about each new place one
## turns up.
##
## `_parse_property` below takes seven parameters, past the five this project
## holds itself to. The signature is Godot's: overriding it with fewer simply
## stops the override working, and the picker has no other entry point. It is
## exempted by name, with that reason written down, rather than the limit being
## raised for everything.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
extends EditorInspectorPlugin

const AttributeProperty = preload(
	"res://addons/GAS_Engine/attributes/gameplay_attribute_editor_property.gd"
)

## The class a property must be for the picker to stand in for it.
const REFERENCE_CLASS: String = "GameplayAttributeRef"


func _can_handle(_object: Object) -> bool:
	return true


## Intercept a property and offer the picker instead of the default field.
##
## Seven parameters, fixed by Godot. See the note above.
func _parse_property(
	_object: Object,
	type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if not is_an_attribute_reference(type, hint_string):
		return false
	add_property_editor(name, AttributeProperty.new())
	return true


## Whether a property holds a typed attribute reference.
##
## The hint string is what says which Resource class a property is for, and it
## is the only thing that does: an exported `GameplayAttributeRef` and an
## exported `Curve` are both TYPE_OBJECT.
static func is_an_attribute_reference(type: Variant.Type, hint_string: String) -> bool:
	return type == TYPE_OBJECT and hint_string == REFERENCE_CLASS
