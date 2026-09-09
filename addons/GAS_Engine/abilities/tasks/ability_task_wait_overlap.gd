## Wait until something worth hitting enters an area the game already put there.
##
## The area is handed in rather than built here, and that is the whole design.
## An engine that instantiated its own Area and shape would be deciding a game's
## collision layers, its shape, and where it sits - four decisions that belong to
## whoever is making the game, and none of which this engine can guess.
##
## It listens to the signals the Area already emits. No physics query, no polling:
## a task that asked the world every frame would answer a different question than
## the one the Area is already answering correctly.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitOverlap extends GameplayAbilityTask

## What came in. Emitted once, immediately before the task succeeds.
signal overlapped(target: Node)

## The Area2D or Area3D being watched. Anything else is refused at creation.
var area: Node = null

## Which overlaps count. Null means all of them.
var filter: GameplayTargetFilter = null

## The first thing that got through the filter.
var overlapped_node: Node = null


static func create(
	ability: GameplayAbility,
	area: Node,
	filter: GameplayTargetFilter = null
) -> AbilityTaskWaitOverlap:
	if not (area is Area2D or area is Area3D):
		push_error("GAS_Engine: wait_overlap needs an Area2D or an Area3D.")
		return null
	var task: AbilityTaskWaitOverlap = AbilityTaskWaitOverlap.new()
	task.owner_ability = ability
	task.area = area
	task.filter = filter
	return task


func _on_start() -> void:
	if area == null or not is_instance_valid(area):
		return
	# Bodies and areas both, because a game decides which of the two its targets
	# are and an engine that listened to one would work for half of them.
	area.connect(&"body_entered", _on_entered)
	area.connect(&"area_entered", _on_entered)


func _on_finish() -> void:
	if area == null or not is_instance_valid(area):
		return
	if area.is_connected(&"body_entered", _on_entered):
		area.disconnect(&"body_entered", _on_entered)
	if area.is_connected(&"area_entered", _on_entered):
		area.disconnect(&"area_entered", _on_entered)


func _on_entered(entered: Node) -> void:
	if is_finished() or entered == null:
		return
	if filter != null and not filter.accepts(_source_asc(), entered):
		return
	overlapped_node = entered
	overlapped.emit(entered)
	succeed()


func _source_asc() -> AbilitySystemComponent:
	return owner_ability.owner_asc if owner_ability != null else null
