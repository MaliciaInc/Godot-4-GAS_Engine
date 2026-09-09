## A spot a person places deliberately, with a rule about where it may go.
##
## The difference from a ground trace is who decides the position: a trace works
## it out from a ray, and this one is told. A game moving a marker with the
## arrow keys, a spell placed by clicking a minimap, an AI choosing a spot -
## all of them write the position and this validates it.
##
## Nothing here queries physics at all, which is why it has no request: a
## placement is a decision about a coordinate. Whoever wants to know who is
## standing on the spot asks a radius provider next.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayPlacementProvider3D extends GameplayLocationProvider3D

## Where the marker is now. Written to between previews.
var position: Vector3 = Vector3.ZERO

## Which way it is turned, for a placement that has a facing - a wall, a cone.
var normal: Vector3 = Vector3.UP

## The last placement this provider refused, for whatever is drawing: a reticle
## shows a person that a spot is not allowed, and it can only do that if
## somebody says so.
var placeable: bool = true


func _aim() -> GameplayAbilityTargetData:
	var found: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	placeable = within_range(position)
	if not placeable:
		# An aim at nothing rather than a refusal: a person dragging a marker
		# past the edge of their range is still aiming, and an ability that
		# ended there would be an ability that cannot be dragged back.
		return found
	found.append_location(position, normal)
	return found
