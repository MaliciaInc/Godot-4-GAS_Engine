## Where the picked cards were when a drag began, so what moved can be said once.
##
## The widget reports that a drag started and that it ended, and nothing about
## what it did. Answering "what actually moved" needs the before as well as the
## after, and holding the before is all this is.
##
## Only the cards whose position changed, and nothing at all when none did: a
## click that happens to be a one-pixel drag is not somebody rearranging their
## graph, and recording it would put an undo in front of the edit they meant.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCardDrag extends RefCounted

var _from: Dictionary[StringName, Vector2] = {}


## Remember where everything selected is standing.
func begun(cards: Dictionary[StringName, ComposerCard]) -> void:
	_from.clear()
	for id: StringName in cards:
		if cards[id].selected:
			_from[id] = cards[id].position_offset


## What ended up somewhere else, and forget the drag either way.
func ended(cards: Dictionary[StringName, ComposerCard]) -> Dictionary[StringName, Vector2]:
	var moved: Dictionary[StringName, Vector2] = {}
	for id: StringName in _from:
		if not cards.has(id):
			continue
		var now: Vector2 = cards[id].position_offset
		if now != _from[id]:
			moved[id] = now
	_from.clear()
	return moved
