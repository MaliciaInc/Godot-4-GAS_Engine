## What the selection becomes, given what it was and what just happened.
##
## Three pure answers, kept apart from the canvas that asks them. They hold no
## state and touch no cards: given a list and a gesture they return the next
## list, which makes them the one part of picking that can be reasoned about
## without a viewport, a zoom level or a tree.
##
## They lived on the canvas until it reached the size this project holds every
## file to. That is a poor reason to move code and a good moment to notice that
## it never belonged there.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerSelection extends RefCounted


## The selection with `id` added, or taken out if it was already in it.
static func toggled(current: Array[StringName], id: StringName) -> Array[StringName]:
	var next: Array[StringName] = current.duplicate()
	if next.has(id):
		next.erase(id)
	else:
		next.append(id)
	return next


## The selection with everything a box swept added to it, and nothing twice.
static func joined(
	current: Array[StringName], swept: Array[StringName]
) -> Array[StringName]:
	var next: Array[StringName] = current.duplicate()
	for id: StringName in swept:
		if not next.has(id):
			next.append(id)
	return next


## Whether this click adds to the selection rather than replacing it.
static func adding(button: InputEventMouseButton) -> bool:
	return button.shift_pressed or button.ctrl_pressed
