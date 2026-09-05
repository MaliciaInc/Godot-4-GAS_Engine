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
## this is about what depends on what. Structural fields - a branch's condition,
## what a return hands back - are still outside what this draws a cable into;
## that is the closure phase's own step and has its own tests.
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


## Join `node`'s value to whichever argument of `other` depends on it.
static func _into(
	graph: ComposerGraph, node: ComposerNode, other: ComposerNode, declared: String
) -> void:
	var slot: int = _argument_naming(other.text, declared)
	if slot < 0:
		return

	graph.connections.append(
		ComposerReader.wire(
			node.id,
			ComposerReader.VALUE_OUT,
			other.id,
			StringName(ComposerReader.ARGUMENT % slot)
		)
	)
	if slot < other.fields.size():
		other.fields[slot].source = ComposerNode.ValueSource.WIRED


## Which argument of `line` is exactly `word`, or -1 when none is.
##
## Position matters: the wire has to land on the slot that uses the value, not
## just on the statement that mentions it somewhere.
static func _argument_naming(line: String, word: String) -> int:
	var open: int = line.find("(")
	if open < 0:
		return -1
	var position: int = 0
	for argument: String in ComposerSubset.arguments_of(line.substr(open + 1)):
		if argument.strip_edges().trim_suffix(")").strip_edges() == word:
			return position
		position += 1
	return -1
