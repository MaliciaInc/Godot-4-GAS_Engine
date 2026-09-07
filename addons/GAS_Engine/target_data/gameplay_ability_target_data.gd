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
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GameplayAbilityTargetData extends RefCounted

const TargetHit = preload("res://addons/GAS_Engine/target_data/gameplay_target_hit.gd")

## This file, by path. Named rather than by its global class name for the reason
## `gameplay_effect_context.gd` gives: this is in an autoload's parse-time
## closure, and an autoload is parsed before Godot has scanned the project for
## class_name declarations - so the global name does not resolve there, not even
## this file's own.
const Self = preload("res://addons/GAS_Engine/target_data/gameplay_ability_target_data.gd")

## Strictly unique target nodes captured by the ability.
var _target_nodes: Array[Node] = []

## Every hit, in capture order. One node may appear in several.
var _hits: Array[TargetHit] = []


#region Appenders
## Append a raw Godot physics result. This is the only untyped entry point.
##
## Returns whether the hit was accepted. A caller that ignores the return value
## still cannot corrupt the payload: a rejected hit adds nothing at all.
## @composer
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
## @composer
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
## @composer
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
## The strictly unique target nodes that are still there, as a copy.
##
## This class validates every hit at the append boundary so nothing
## half-understood is stored. Handing out the array it stores them in let
## a caller append straight past that.
##
## Still there, because aiming has a middle. A target picked at the start of
## a preview can be dead by the time somebody confirms, and what `confirm()`
## hands over is the last preview rather than a fresh look at the world. A
## freed Node compares equal to null in Godot, so a caller looping over these
## and skipping nulls was already skipping it - and a caller counting them was
## being told an ability hit one more thing than it did.
## @composer
func get_target_nodes() -> Array[Node]:
	var alive: Array[Node] = []
	for node: Node in _target_nodes:
		if is_instance_valid(node):
			alive.append(node)
	return alive


## Every registered hit, as a copy, for multi-hit and AoE processing.
## @composer
func get_all_hits() -> Array[TargetHit]:
	return _hits.duplicate()


## Only the hits belonging to one node, for precision calculations such as
## "did this particular bullet hit the head shape?".
## @composer
func get_hits_for_node(node: Node) -> Array[TargetHit]:
	var specific: Array[TargetHit] = []
	for hit: TargetHit in _hits:
		if hit.collider == node:
			specific.append(hit)
	return specific


## The first hit recorded for one node, or null when none was.
##
## A cue plays in one place. A target struck by two of an area effect's
## traces is still one target being hit, and the first is the one the
## targeting reported first - not an invented average of two surfaces.
## @composer
func first_hit_for(node: Node) -> TargetHit:
	var hits: Array[TargetHit] = get_hits_for_node(node)
	return hits[0] if not hits.is_empty() else null


## An aim of this one's own, keeping only what `only` names.
##
## Two things at once because they are one operation. An area effect is aimed
## once and lands on several, and what each of them was hit by is different:
## where the sweep touched them, which shape, at what angle. Handing every
## victim the whole aim tells each of them about everybody else - a "did this
## hit my head" check answering yes because it hit somebody else's head - and
## handing them nothing, which is what happened before, tells them nothing
## about themselves either.
##
## Always a new object, never the one it was handed. Target data is mutable, so
## two victims sharing one is either of them changing what the other sees: a
## channelled ability dropping a target that walked out of the area would drop
## it from the other victim's data as well.
##
## `only` null keeps everything, which is the copy an application needs when it
## was aimed at one thing to begin with.
## @composer
func copied(only: Node = null) -> Self:
	var theirs: Self = Self.new()
	for node: Node in _target_nodes:
		if only != null and node != only:
			continue
		theirs._target_nodes.append(node)
	for hit: TargetHit in _hits:
		if only == null or hit.collider == only:
			theirs._hits.append(hit)
	return theirs


## Whether anything it aimed at is still there to be hit.
## @composer
func has_targets() -> bool:
	return not get_target_nodes().is_empty()
#endregion


#region Mutators
## Remove a node and every hit that belongs to it. Used by channelled and aura
## abilities when a target physically leaves the area.
## @composer
func force_remove_target(node: Node) -> void:
	_target_nodes.erase(node)
	for index: int in range(_hits.size() - 1, -1, -1):
		if _hits[index].collider == node:
			_hits.remove_at(index)


## @composer
func clear() -> void:
	_target_nodes.clear()
	_hits.clear()
#endregion
