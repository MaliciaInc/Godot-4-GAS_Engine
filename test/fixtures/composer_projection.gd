## The part of a projection a test usually means.
##
## A graph holds more than the file does: Entry is a node so the canvas has
## somewhere to begin a wire, and support headers are nodes so the reader can
## account for every line. Neither is a statement, so a test asking "what was
## read" wants this rather than `graph.nodes` - and it wants it in one place,
## because twelve copies of the same four lines is twelve chances to disagree
## about what counts.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerProjection extends RefCounted


## The nodes a line of the file backs, in the order they were read.
static func statements(graph: ComposerGraph) -> Array[ComposerNode]:
	var found: Array[ComposerNode] = []
	for node: ComposerNode in graph.nodes:
		if node.source_backed:
			found.append(node)
	return found
