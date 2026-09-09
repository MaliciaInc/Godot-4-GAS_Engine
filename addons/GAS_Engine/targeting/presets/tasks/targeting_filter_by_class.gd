## Keep only what is the kind of thing this step names.
##
## By script rather than by class name string, because a name is checked by
## nobody: a typo in one produces a step that quietly keeps nothing, and the
## first person to notice is whoever wondered why the spell stopped working.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingFilterByClass extends GameplayTargetingTask

## The script a target's node must carry, directly or by inheritance.
@export var required_script: Script = null

## Keep what is NOT the named kind instead. For "everything but the walls".
@export var invert: bool = false


func execute(
	input: GameplayAbilityTargetData, _source_asc: AbilitySystemComponent
) -> GameplayAbilityTargetData:
	if required_script == null:
		return input
	for node: Node in input.get_target_nodes():
		if _is_the_kind(node) == invert:
			input.force_remove_target(node)
	return input


## Whether this node carries the named script, or something that extends it.
func _is_the_kind(node: Node) -> bool:
	var carried: Script = node.get_script() as Script
	while carried != null:
		if carried == required_script:
			return true
		carried = carried.get_base_script()
	return false
