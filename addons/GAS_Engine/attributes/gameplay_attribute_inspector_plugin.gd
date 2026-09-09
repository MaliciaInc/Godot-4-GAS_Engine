## Offers the attribute picker wherever a `GameplayAttributeRef` is authored.
##
## By the property's type rather than by its name: a reference is a reference
## wherever it appears - on a modifier, on a cue binding, on a capture - and a
## plugin matching on names would have to be told about each new place one
## turns up.
##
## The matching and Godot's seven-parameter override live in
## GASResourceInspectorPlugin, which the tag query editor uses too. What is here
## is the two things that differ: which class, and which editor.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
extends GASResourceInspectorPlugin

const AttributeProperty = preload(
	"res://addons/GAS_Engine/attributes/gameplay_attribute_editor_property.gd"
)

## The class a property must be for the picker to stand in for it.
const REFERENCE_CLASS: String = "GameplayAttributeRef"


func edited_class() -> String:
	return REFERENCE_CLASS


func editor_for_property() -> EditorProperty:
	return AttributeProperty.new()


## Whether a property holds a typed attribute reference.
static func is_an_attribute_reference(type: Variant.Type, hint_string: String) -> bool:
	return GASResourceInspectorPlugin.stands_in_for(type, hint_string, REFERENCE_CLASS)
