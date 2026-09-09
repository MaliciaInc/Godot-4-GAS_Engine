## Aiming a 2D ray, for as long as somebody is aiming it.
##
## The request is a field rather than an argument, and that is the whole
## difference from calling the service directly: a preview is the same query
## asked again as the aim moves, so what moves is the request and what stays is
## the provider. Whatever the game aims with - input, a camera, a cursor - writes
## to the request, and none of that reaches the physics service.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayRaycastTargetProvider2D extends GameplayTargetProvider

## What is being aimed. Written to between previews and read here.
var request: GameplayRaycastRequest2D = GameplayRaycastRequest2D.new()


func _aim() -> GameplayAbilityTargetData:
	var world: World2D = world_2d()
	if world == null:
		return GameplayAbilityTargetData.new()
	return GameplayTargetingService.raycast_2d(source_asc(), world, request)
