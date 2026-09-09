## Put what was found in order of how far away it is, and optionally keep only
## the first few.
##
## The step that makes "the nearest three" expressible. Sorting and keeping are
## one step rather than two because keeping the first N is meaningless without
## an order, and a preset that authored them separately could author the take
## before the sort.
##
## Ties are broken by the order the targets were found in, so the same world
## produces the same answer twice. A sort that left ties to chance would be a
## preset a server could not check.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name TargetingSortByDistance extends GameplayTargetingTask

## Furthest first instead.
@export var descending: bool = false

## How many to keep. Zero keeps all of them.
@export var keep: int = 0


func execute(
	input: GameplayAbilityTargetData, source_asc: AbilitySystemComponent
) -> GameplayAbilityTargetData:
	if source_asc == null:
		return input
	var from: Node3D = source_asc.get_effect_target() as Node3D
	if from == null:
		return input

	var found: Array[Node] = input.get_target_nodes()
	var ordered: Array[Node] = _ordered(found, from.global_position)

	var kept: Array[Node] = ordered
	if keep > 0 and ordered.size() > keep:
		kept = ordered.slice(0, keep)

	var answer: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for node: Node in kept:
		for hit: GameplayTargetHit in input.get_hits_for_node(node):
			answer.append_node(node)
			break
	# Places have no distance from anybody and are not sorted; they are carried
	# through, because a step about actors must not silently drop the spot an
	# earlier step found.
	for hit: GameplayTargetHit in input.get_all_hits():
		if hit.collider == null and hit.has_position:
			if hit.space_kind == GameplayTargetHit.SpaceKind.TWO_D:
				answer.append_location(hit.position_2d, hit.normal_2d)
			else:
				answer.append_location(hit.position_3d, hit.normal_3d)
	return answer


## The targets in distance order, ties broken by where they already were.
##
## An insertion rather than a sort_custom, because Godot's sort is not stable
## and a preset whose answer depended on which of two equidistant targets the
## sort happened to keep first would be one a server could not reproduce.
func _ordered(found: Array[Node], origin: Vector3) -> Array[Node]:
	var ordered: Array[Node] = []
	for node: Node in found:
		var mine: float = _distance_of(node, origin)
		var at: int = ordered.size()
		for index: int in ordered.size():
			var theirs: float = _distance_of(ordered[index], origin)
			if (mine < theirs) != descending and not is_equal_approx(mine, theirs):
				at = index
				break
		ordered.insert(at, node)
	return ordered


## How far a target is, or infinity for one that is nowhere - which puts it
## last ascending and first descending, and either way somewhere definite.
func _distance_of(node: Node, origin: Vector3) -> float:
	var spatial: Node3D = node as Node3D
	if spatial == null:
		return INF
	return spatial.global_position.distance_to(origin)
