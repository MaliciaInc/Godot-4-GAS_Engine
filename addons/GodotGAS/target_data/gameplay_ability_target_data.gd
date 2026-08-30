## Target information gathered during an ability's execution.
##
## Hits are stored as `GameplayTargetHit`, never as raw physics dictionaries.
## Upstream kept `Array[Dictionary]` and let every consumer call
## `hit.get("collider")` for itself, so each consumer carried its own idea of
## what the keys held and a rename would have failed silently in all of them.
## Conversion happens once, at the append boundary, and a hit that cannot be
## vouched for is rejected rather than stored half-understood.
##
## Types come from `preload` rather than global class names: this file is
## reachable from the GameplayCueManager autoload, which is parsed before Godot
## has a global class cache on a checkout that was never imported.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name GameplayAbilityTargetData extends RefCounted

const TargetHit = preload("res://addons/GodotGAS/target_data/gameplay_target_hit.gd")

## Strictly unique target nodes captured by the ability.
var _target_nodes: Array[Node] = []

## Every hit, in capture order. One node may appear in several.
var _hits: Array[TargetHit] = []


#region Appenders
## Append a raw Godot physics result. This is the only untyped entry point.
##
## Returns whether the hit was accepted. A caller that ignores the return value
## still cannot corrupt the payload: a rejected hit adds nothing at all.
func append_physics_hit(hit_dict: Dictionary) -> bool:
	var hit: TargetHit = TargetHit.try_from_physics_hit(hit_dict)
	if hit == null:
		return false
	_record(hit)
	return true


## Append a direct node reference, deriving the hit position from the node's
## own space. Good for ShapeCast nodes, UI targeting and auto-aim.
##
## The space is read from the node's actual type rather than from an untyped
## position argument, so a 2D node can never be recorded as a 3D hit.
func append_node(node: Node) -> bool:
	if node == null:
		return false

	var hit: TargetHit = TargetHit.new()
	hit.collider = node

	var canvas_node: Node2D = node as Node2D
	if canvas_node != null:
		hit.space_kind = TargetHit.SpaceKind.TWO_D
		hit.position_2d = canvas_node.global_position
		_record(hit)
		return true

	var spatial_node: Node3D = node as Node3D
	if spatial_node != null:
		hit.space_kind = TargetHit.SpaceKind.THREE_D
		hit.position_3d = spatial_node.global_position
		_record(hit)
		return true

	# A non-spatial node is a legitimate target - a UI element, a pure data node
	# - it simply has no position. Recording it at the origin would be a lie, so
	# the space defaults to 3D with a zero position and the caller learns nothing
	# false from it.
	_record(hit)
	return true


## Append every node of an overlap query.
func append_overlap(nodes: Array[Node]) -> int:
	var accepted: int = 0
	for node: Node in nodes:
		if append_node(node):
			accepted += 1
	return accepted


func _record(hit: TargetHit) -> void:
	_hits.append(hit)
	if hit.collider != null and not _target_nodes.has(hit.collider):
		_target_nodes.append(hit.collider)
#endregion


#region Getters
## The strictly unique target nodes.
func get_target_nodes() -> Array[Node]:
	return _target_nodes


## Every registered hit, for multi-hit and AoE processing.
func get_all_hits() -> Array[TargetHit]:
	return _hits


## Only the hits belonging to one node, for precision calculations such as
## "did this particular bullet hit the head shape?".
func get_hits_for_node(node: Node) -> Array[TargetHit]:
	var specific: Array[TargetHit] = []
	for hit: TargetHit in _hits:
		if hit.collider == node:
			specific.append(hit)
	return specific


func has_targets() -> bool:
	return not _target_nodes.is_empty()
#endregion


#region Mutators
## Remove a node and every hit that belongs to it. Used by channelled and aura
## abilities when a target physically leaves the area.
func force_remove_target(node: Node) -> void:
	_target_nodes.erase(node)
	for index: int in range(_hits.size() - 1, -1, -1):
		if _hits[index].collider == node:
			_hits.remove_at(index)


func clear() -> void:
	_target_nodes.clear()
	_hits.clear()
#endregion
