## A 2D line to trace, in world coordinates.
##
## World coordinates, never a mouse position or a viewport point. The ability
## system is told where to look; working out where the player pointed belongs to
## whatever owns the camera, and a GAS that read input would be untestable
## without one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayRaycastRequest2D extends RefCounted

var from: Vector2 = Vector2.ZERO
var to: Vector2 = Vector2.ZERO

var collision_mask: int = 0xFFFFFFFF

var collide_with_bodies: bool = true

## Off by default: an area is usually a trigger volume rather than something a
## shot should stop against.
var collide_with_areas: bool = false

## Optional. Without one, whatever the trace hits is taken as found.
var filter: GameplayTargetFilter = null
