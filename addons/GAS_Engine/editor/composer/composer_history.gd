## What the file said before, and what it said after that.
##
## Undo over the **text**, not over the graph. Everything on the canvas is a
## projection of the file: the nodes, the cables, the marks and where each card
## sits are all worked out again from the source every time it is read. So
## putting the source back puts all of it back, exactly, with nothing to invert
## and nothing that can be inverted wrongly.
##
## The alternative is a stack of operations that each know how to undo
## themselves, and every one of them is a chance to be a little wrong - the
## classic being an undo that restores a value and forgets the cable it broke.
## There is no such class of bug here, because there is no such stack.
##
## Depth is bounded. A body is a few kilobytes and sixty-four of them is
## nothing, but unbounded is not a size - it is a decision nobody made.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerHistory extends RefCounted

const DEPTH: int = 64

var _done: Array[String] = []
var _undone: Array[String] = []


## Remember what the file said before the change that is about to happen.
##
## Anything that could be undone forward is dropped: once somebody edits after
## undoing, the branch they undid is not where they are any more, and offering
## to redo into it would take them somewhere they never were.
func record(before: String) -> void:
	_done.append(before)
	_undone.clear()
	if _done.size() > DEPTH:
		_done.remove_at(0)


func can_undo() -> bool:
	return not _done.is_empty()


func can_redo() -> bool:
	return not _undone.is_empty()


## Go back one, handing over what is current so it can be come back to.
##
## Returns `current` unchanged when there is nothing to go back to, so a caller
## that asked without checking gets the file it already had rather than an empty
## one.
func undo(current: String) -> String:
	if _done.is_empty():
		return current
	_undone.append(current)
	return _done.pop_back()


func redo(current: String) -> String:
	if _undone.is_empty():
		return current
	_done.append(current)
	return _undone.pop_back()


## Start again, for a file that has just been opened.
func forget() -> void:
	_done.clear()
	_undone.clear()
