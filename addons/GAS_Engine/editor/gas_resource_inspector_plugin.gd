## An inspector plugin that stands in for exactly one Resource class.
##
## The shape both the attribute picker and the tag query editor are: match a
## property by the class it holds, and put our own editor there instead of the
## default one. What differs between them is the class name and which editor,
## which is what a subclass answers.
##
## `_parse_property` takes seven parameters, past the five this project holds
## itself to. The signature is Godot's: overriding it with fewer simply stops
## the override working. It is written once here rather than once per picker,
## so the exemption is one file rather than one per Resource class somebody
## wants an editor for.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
class_name GASResourceInspectorPlugin extends EditorInspectorPlugin


## The Resource class this plugin offers an editor for.
func edited_class() -> String:
	return ""


## A fresh editor for one property. One per property, not one shared: two
## properties of the same class are two rows, each with its own state.
func editor_for_property() -> EditorProperty:
	return null


func _can_handle(_object: Object) -> bool:
	return true


## Intercept a property and offer our editor instead of the default field.
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
	if not stands_in_for(type, hint_string, edited_class()):
		return false
	add_property_editor(name, editor_for_property())
	return true


## Whether a property holds the class named.
##
## The hint string is what says which Resource class a property is for, and it
## is the only thing that does: an exported `GameplayTagQuery` and an exported
## `Curve` are both TYPE_OBJECT.
static func stands_in_for(
	type: Variant.Type, hint_string: String, class_named: String
) -> bool:
	return type == TYPE_OBJECT and hint_string == class_named
