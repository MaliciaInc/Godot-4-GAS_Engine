## Where a ray from the camera meets the ground, for as long as somebody is
## aiming it.
##
## The aim a ground-targeted spell is: a person points somewhere and the engine
## works out which spot on the world that is. What comes back is a location -
## a place with nothing standing at it - because that is the honest answer, and
## whatever wants to know who is standing there asks a radius provider next.
##
## Every query goes through GameplayTargetingService, and the ray is written by
## whoever is aiming - a camera, a cursor, an AI. None of that reaches physics
## through this class.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayGroundTraceProvider3D extends GameplayLocationProvider3D

## The ray being aimed. Written to between previews.
var request: GameplayRaycastRequest3D = GameplayRaycastRequest3D.new()

## Where the last trace landed, and whether it landed anywhere. Kept so a caller
## that wants the spot rather than the whole aim can have it without unpacking
## the target data again.
var landed_at: Vector3 = Vector3.ZERO
var landed: bool = false


func _aim() -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	landed = false
	var world: World3D = world_3d()
	if world == null:
		return found

	var struck: GameplayAbilityTargetData = GameplayTargetingService.raycast_3d(
		source_asc(), world, request
	)
	for hit: GameplayTargetHit in struck.get_all_hits():
		if not hit.has_position:
			continue
		if not within_range(hit.position_3d):
			continue
		landed_at = hit.position_3d
		landed = true
		# A place, not the thing the ray happened to strike: what a ground-aimed
		# spell is aimed at is the ground, and reporting the collider would make
		# every ground spell also a hit on whatever the terrain node is.
		found.append_location(hit.position_3d, hit.normal_3d)
		break
	return found
