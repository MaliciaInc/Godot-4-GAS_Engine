## Keep only what its ability system answers this query about.
##
## The step "enemies only" is made of: every faction is a tag, and the query is
## the sentence about which of them count. A target with no ability system at
## all answers nothing, and is dropped - a wall cannot be an enemy.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingFilterByTagQuery extends GameplayTargetingTask

@export var query: GameplayTagQuery = null

## Keep what does NOT match instead.
@export var invert: bool = false


func execute(
	input: GameplayAbilityTargetData, _source_asc: AbilitySystemComponent
) -> GameplayAbilityTargetData:
	if query == null or query.is_empty():
		return input
	for node: Node in input.get_target_nodes():
		if _matches(node) == invert:
			input.force_remove_target(node)
	return input


func _matches(node: Node) -> bool:
	var asc: AbilitySystemComponent = AbilitySystemLocator.find_for_node(node)
	if asc == null:
		return false
	return query.matches_runtime(asc.tags)
