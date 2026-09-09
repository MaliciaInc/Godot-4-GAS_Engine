## Everything inside a circle, for as long as somebody is aiming it - in two
## dimensions.
##
## A sweep whose centre moves. What is different from the overlap provider it
## sits beside is what a person does with it: this one is aimed at a place on
## the ground and shows a radius while they choose it, so the centre is written
## from wherever they are pointing and the radius is authored once.
##
## Every query goes through GameplayTargetingService. A provider that talked to
## physics itself would be a second place where a filter is applied and an
## actor's several colliders are collapsed into one target.
##
## The 3D mirror of this file is GameplayRadiusProvider3D. Two files rather
## than one because Godot's two dimensions share no base and no vector type.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayRadiusProvider2D extends GameplayTargetProvider

## What is being aimed. Written to between previews; the radius and the filter
## are authored once and the centre moves.
var request: GameplayOverlapRequest2D = GameplayOverlapRequest2D.new()

## How far from the caster the centre may be placed. Zero means anywhere, which
## is what an aim with no range restriction is.
var max_range: float = 0.0


func _aim() -> GameplayAbilityTargetData:
	var world: World2D = world_2d()
	if world == null or not _within_range(request.center):
		return GameplayAbilityTargetData.new()
	return GameplayTargetingService.overlap_2d(source_asc(), world, request)


## What this provider can check about a claim, which is the range it enforces,
## the radius it was authored with, and the filter it applies.
##
## Not everything: a client claiming it hit somebody who was standing there a
## frame ago is a question about time, and nothing here can answer it. What this
## does refuse is a claim that is impossible under this provider's own numbers.
func validate_authoritative(
	data: GameplayAbilityTargetData, checking_asc: AbilitySystemComponent
) -> bool:
	if data == null or checking_asc == null:
		return false
	if request.radius <= 0.0:
		return false
	if not _within_range(request.center):
		return false
	for node: Node in data.get_target_nodes():
		if node == null or not is_instance_valid(node):
			return false
		if request.filter != null and not request.filter.accepts(checking_asc, node):
			return false
		var spatial: Node2D = node as Node2D
		if spatial == null:
			continue
		if spatial.global_position.distance_to(request.center) > request.radius:
			return false
	return true


## Whether the centre is somewhere this caster could have put it.
func _within_range(centre: Vector2) -> bool:
	if max_range <= 0.0:
		return true
	var from: Node2D = avatar() as Node2D
	if from == null:
		return true
	return from.global_position.distance_to(centre) <= max_range
