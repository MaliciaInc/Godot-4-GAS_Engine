## Which statement's value feeds which statement's argument.
##
## A local's value reaches every later statement that names it. Read by name
## rather than by scope analysis, which the subset makes safe: a body with no
## loops and no lambdas has one flat set of names, so a later line mentioning
## `target` means that `target`.
##
## Only the exact spelling draws a cable. Two different things used to be one: a
## cable says "this statement needs what that one produced", which is true of
## `apply(damage, pick.target_data)` - the statement plainly depends on `pick`.
## It is separately true, and only sometimes, that the argument *is* the local
## and can be re-pointed at another one; that is the exact spelling, and only
## that spelling. Tying both to it drew almost nothing on real code, because
## real code reaches into a local far more often than it passes one whole - but
## the alternative is a cable a person can see and cannot move, which is the one
## thing this projection may not offer.
##
## Split out of the reader because the reader is about what each line is and
## this is about what depends on what. Every data field is looked at, not only
## a call's arguments: `if ready:` after `var ready: bool = can_activate()` is
## the same dependency written a different way, and drawing one and not the
## other was a canvas where half the value flow was invisible.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerDataWires extends RefCounted


## Draw every value cable the body states, onto a graph whose nodes are read.
static func apply(graph: ComposerGraph) -> void:
	for node: ComposerNode in graph.nodes:
		var declared: String = ComposerReader.local_name(node.text)
		if declared.is_empty():
			continue
		for other: ComposerNode in graph.nodes:
			if other.span.first_line <= node.span.last_line:
				continue
			_into(graph, node, other, declared)


## Join `node`'s value to every field of `other` that is exactly it.
##
## Read off the fields rather than off the text. The fields already know what
## each one holds - an argument, a condition, what a return hands back - and
## parsing the statement again here would answer for arguments only, which is
## how a branch fed by a local came out looking like a branch fed by nothing.
##
## Every field, not the first: `apply(target, target)` passes one value twice,
## and a person who unplugs one of those two has to be left with the other.
static func _into(
	graph: ComposerGraph, node: ComposerNode, other: ComposerNode, declared: String
) -> void:
	for position: int in other.fields.size():
		if other.fields[position].display.strip_edges() != declared:
			continue
		var pin: ComposerNode.Port = other.pin_for_field(position)
		if pin == null:
			continue
		graph.connections.append(
			ComposerReader.wire(node.id, ComposerReader.VALUE_OUT, other.id, pin.id)
		)
		other.fields[position].source = ComposerNode.ValueSource.WIRED
