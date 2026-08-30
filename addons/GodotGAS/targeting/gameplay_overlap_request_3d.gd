## A 3D sphere to sweep, in world coordinates.
##
## The 3D twin of the 2D overlap. Like the raycast pair, kept as its own type so
## a caller cannot hand a flat centre to a query that needs a point in space.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayOverlapRequest3D extends RefCounted

var center: Vector3 = Vector3.ZERO

## Clamped to zero or more when the query runs. A negative radius is a caller's
## mistake, and an empty sweep is a better answer than an undefined one.
var radius: float = 0.0

var collision_mask: int = 0xFFFFFFFF

var collide_with_bodies: bool = true

## On for a sweep more often than for a trace, but still the caller's decision.
var collide_with_areas: bool = false

var filter: GameplayTargetFilter = null
