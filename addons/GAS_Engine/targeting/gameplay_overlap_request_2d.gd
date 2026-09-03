## A 2D circle to sweep, in world coordinates.
##
## An overlap answers "what is in here", which is a different question from a
## trace's "what does this line meet first", and physics answers it with less
## information: colliders, but no impact point and no surface normal. Nothing
## downstream is given an invented one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayOverlapRequest2D extends RefCounted

var center: Vector2 = Vector2.ZERO

## Clamped to zero or more when the query runs. A negative radius is a caller's
## mistake, and an empty sweep is a better answer than an undefined one.
var radius: float = 0.0

var collision_mask: int = 0xFFFFFFFF

var collide_with_bodies: bool = true

## On for a sweep more often than for a trace, but still the caller's decision.
var collide_with_areas: bool = false

## Optional, and its absence does NOT mean what it means on a trace. A trace
## with no filter reports whatever it hit; a sweep with no filter still keeps
## only what has an ability system, because a sweep answers by actor and the
## actor is who the ability system belongs to. Scenery inside the circle is
## not a target, with or without one - see GameplayTargetingService._take_sweep.
##
## Without a filter the caster is also included: excluding it is
## GameplayTargetFilter.exclude_source's job, and there is no filter to ask.
var filter: GameplayTargetFilter = null

## How many colliders physics may answer with before it stops looking.
##
## Godot's own default is 32, and it truncates in silence. That is a second
## limit sitting under GameplayTargetFilter.max_targets and applied in the wrong
## order: physics stops before the sweep has dropped scenery and collapsed an
## actor's several colliders into one target, so an author who asked for twenty
## targets could be handed sixteen and never be told why. Raised here so the
## only limit that decides is one somebody wrote. Lower it to pay less for a
## sweep that cannot reach a crowd. Clamped to one or more when the query runs.
var max_results: int = 256
