## What a person sees while they are aiming, in two dimensions.
##
## A Node the game authors and the engine only drives. Everything here is a
## question the aiming already answered - where it is pointing, whether that is
## a legal place to put it, how big the area is - and what a reticle does with
## those is entirely the project's business: a sprite, a ring of particles, a
## shader on the tilemap.
##
## The 3D mirror of this file is GameplayTargetReticle3D. They are two files
## rather than one because Godot's 2D and 3D nodes share no base and no vector
## type: the only way to write the pair once would be to take positions as
## Variant, which is a dynamic boundary in the middle of our own code.
##
## No provider ever holds one of these. A provider works out what is being
## aimed at and announces it; something else decides whether to draw. Keeping a
## reference to the reticle inside the provider would make aiming and drawing
## one thing, and then a headless server would be instantiating art.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetReticle2D extends Node2D

## Whether the reticle turns to face whoever is aiming it. Read by `follow`,
## and meaningless to a reticle that does not draw anything directional.
var faces_source: bool = false

## The last aim this was shown. Kept so a subclass overriding `_redraw` has the
## whole of what it was told rather than only the part it asked about.
var aimed: GameplayAbilityTargetData = null

## Whether what is being aimed at is a legal thing to aim at.
var valid: bool = true

## How big the area being aimed is, in pixels. Zero for an aim that has no
## area - a single target, a line.
var radius: float = 0.0


## Move to what is being aimed at now.
##
## The first located hit is where the reticle goes, because that is the point
## the aim is about; an aim with nothing located leaves it where it was, which
## is what a person expects when they sweep past the edge of the world.
## @composer
func follow(data: GameplayAbilityTargetData) -> void:
	aimed = data
	if data == null:
		return
	for hit: GameplayTargetHit in data.get_all_hits():
		if hit.has_position and hit.space_kind == GameplayTargetHit.SpaceKind.TWO_D:
			global_position = hit.position_2d
			break
	_redraw()


## @composer
func set_valid(value: bool) -> void:
	valid = value
	_redraw()


## @composer
func face_source(value: bool) -> void:
	faces_source = value
	_redraw()


## @composer
func set_radius(value: float) -> void:
	radius = value
	_redraw()


## Called after anything changes. Empty here: the base reticle is a position
## and four facts about it, and what to draw is the project's answer.
func _redraw() -> void:
	pass
