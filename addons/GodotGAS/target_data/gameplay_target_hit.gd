## One physics hit, converted at the engine boundary into a typed value.
##
## Replaces the `Array[Dictionary]` upstream stored. The raw dictionary is never
## kept: it is validated once, here, and either becomes a GameplayTargetHit or
## is rejected. Keeping it would push `hit.get("collider")` into every consumer,
## and each consumer would guess differently about what the key contains.
##
## The 2D/3D boundary is fixed by `space_kind` rather than by whichever field
## happens to be non-zero.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayTargetHit extends RefCounted

enum SpaceKind { TWO_D, THREE_D }

var collider: Node = null
var space_kind: SpaceKind = SpaceKind.THREE_D

var position_2d: Vector2 = Vector2.ZERO
var normal_2d: Vector2 = Vector2.ZERO

var position_3d: Vector3 = Vector3.ZERO
var normal_3d: Vector3 = Vector3.ZERO


## Convert a Godot physics result. Returns null on anything it cannot vouch for.
##
## This is the only place in the addon allowed to read an untyped physics
## dictionary. A mixed-dimension hit - a Vector2 position with a Vector3 normal
## - is rejected rather than half-converted, because a partially populated hit
## reads as valid to every caller downstream.
static func try_from_physics_hit(hit: Dictionary) -> GameplayTargetHit:
	var raw_collider: Variant = hit.get("collider")
	var raw_position: Variant = hit.get("position")
	var raw_normal: Variant = hit.get("normal")

	if not raw_collider is Node:
		return null

	var result: GameplayTargetHit = GameplayTargetHit.new()
	result.collider = raw_collider

	if raw_position is Vector2 and raw_normal is Vector2:
		result.space_kind = SpaceKind.TWO_D
		result.position_2d = raw_position
		result.normal_2d = raw_normal
		return result

	if raw_position is Vector3 and raw_normal is Vector3:
		result.space_kind = SpaceKind.THREE_D
		result.position_3d = raw_position
		result.normal_3d = raw_normal
		return result

	return null
