## A 2D circle to sweep, in world coordinates.
##
## An overlap answers "what is in here", which is a different question from a
## trace's "what does this line meet first", and physics answers it with less
## information: colliders, but no impact point and no surface normal. Nothing
## downstream is given an invented one.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayOverlapRequest2D extends RefCounted

var center: Vector2 = Vector2.ZERO

## Clamped to zero or more when the query runs. A negative radius is a caller's
## mistake, and an empty sweep is a better answer than an undefined one.
var radius: float = 0.0

var collision_mask: int = 0xFFFFFFFF

var collide_with_bodies: bool = true

## On for a sweep more often than for a trace, but still the caller's decision.
var collide_with_areas: bool = false

var filter: GameplayTargetFilter = null
