## A 3D line to trace, in world coordinates.
##
## The 3D twin of the 2D request. They are separate types rather than one
## carrying a dimension flag, because a Vector2 and a Vector3 are not
## interchangeable and a single type would have to hold both and trust the
## caller to have set the right one.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayRaycastRequest3D extends RefCounted

var from: Vector3 = Vector3.ZERO
var to: Vector3 = Vector3.ZERO

var collision_mask: int = 0xFFFFFFFF

var collide_with_bodies: bool = true

## Off by default: an area is usually a trigger volume rather than something a
## shot should stop against.
var collide_with_areas: bool = false

## Optional. Without one, whatever the trace hits is taken as found.
var filter: GameplayTargetFilter = null
