## The base class every attribute module inherits from.
##
## Do not instantiate directly; inherit to declare specific stats and to clamp
## them. Two clamp hooks exist, and they are not interchangeable:
##
##   pre_attribute_base_change  guards the durable value
##   pre_attribute_change       guards the derived value
##
## Upstream had only the second. With one hook, 500 damage against 100 health
## leaves `base = -400` while `current` clamps to 0, so a later heal of 30
## brings current back to 0 rather than 30 and the character stays dead through
## a full heal. Preventing exactly that is what the base clamp is for.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@tool @abstract
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name AttributeSet extends Resource


#region Core Virtuals
## Called before a durable base value is written. Return the value that may
## actually be stored.
##
## This is the hook that keeps health from going to -400 and staying there.
func pre_attribute_base_change(_attribute_name: StringName, proposed_base_value: float) -> float:
	return proposed_base_value


## Called before a derived current value is written, after the aggregator has
## composed base and contributions. Return the value that may actually be shown.
func pre_attribute_change(_attribute_name: StringName, proposed_current_value: float) -> float:
	return proposed_current_value


## Called after a current value actually changed. Use it to react to dependent
## attributes, e.g. clamping Health when MaxHealth drops.
func post_attribute_change(
	_asc: Node, _attribute_name: StringName, _old_value: float, _new_value: float
) -> void:
	pass


## Every attribute this set declares, by name. The runtime uses it to recompose
## dependent attributes without guessing at the set's property list.
##
## The default reads the exported properties, so a set that simply declares
## `@export var health: AttributeData` needs no boilerplate.
func get_attribute_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for property: Dictionary in get_property_list():
		var property_name: String = property.get("name", "")
		if property_name.is_empty():
			continue
		if get(property_name) is AttributeData:
			names.append(StringName(property_name))
	return names
#endregion
