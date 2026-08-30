## A grant caused by an ordinary scene-tree Node - a weapon, a caster, a trap.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAbilityNodeSource extends GameplayAbilitySource

var node: Node = null


## The node's path or name, for diagnostics only, and only while it is still
## valid. A source string is never gameplay identity: nothing compares two
## grants by re-deriving and matching this.
func source_id() -> StringName:
	if node == null or not is_instance_valid(node):
		return &""
	return StringName(String(node.name))
