## The lines of a `.gd` a projected node came from.
##
## This is the load-bearing part of the whole Composer. The graph is a view of a
## file rather than a thing of its own, so every node has to be able to point
## back at the exact text it was read from. Without that:
##
## - selecting a node could not highlight its code, and vice versa;
## - leaving to the script editor could not put the caret anywhere useful;
## - the writer would have no idea what to replace, and would have to rewrite
##   the whole method - taking every comment and hand-written line with it.
##
## Lines are 1-based and the range includes both ends, because that is how a
## person reads a file and how Godot's script editor numbers it. Converting at
## the boundary is one subtraction; converting in the middle is a bug per call
## site.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerSpan extends RefCounted

const NO_LINE: int = 0

var first_line: int = NO_LINE
var last_line: int = NO_LINE


func _init(first: int = NO_LINE, last: int = NO_LINE) -> void:
	first_line = first
	last_line = last


## A span nothing was read from. Distinct from a one-line span, which is why
## the empty value is not `first_line == last_line`.
func is_valid() -> bool:
	return first_line != NO_LINE and last_line >= first_line


func contains(line: int) -> bool:
	return is_valid() and line >= first_line and line <= last_line


func line_count() -> int:
	return 0 if not is_valid() else last_line - first_line + 1
