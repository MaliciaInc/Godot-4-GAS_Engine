## Asking a reread graph what runs after what, the way a test needs to.
##
## Every test about execution ends in the same three questions: which statement
## says that, does this pin of it reach that one, and - when the answer is no -
## what does the body actually say now. Written twice they were two spellings of
## one question, which is one more than there should be: a helper that found a
## statement by a slightly different rule would make two test files disagree
## about the same file.
##
## Nothing here asserts. A fixture that judged would be a second set of rules to
## keep in step with the real ones.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowProbe extends RefCounted


## The statement whose line says `said`, or nothing.
static func at(graph: ComposerGraph, said: String) -> ComposerNode:
	for node: ComposerNode in graph.nodes:
		if node.source_backed and node.text.contains(said):
			return node
	return null


## Whether one statement leaves by `pin` into another statement's run of control.
static func runs(
	graph: ComposerGraph, from_said: String, pin: StringName, to_said: String
) -> bool:
	var leaving: ComposerNode = at(graph, from_said)
	var arriving: ComposerNode = at(graph, to_said)
	if leaving == null or arriving == null:
		return false
	return graph.has_connection(
		ComposerReader.wire(leaving.id, pin, arriving.id, ComposerReader.EXEC_IN)
	)


## The body of `source`, one statement per entry, for a failure to print.
static func body_of(source: String) -> PackedStringArray:
	var said: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		if line.begins_with("\t"):
			said.append(line.strip_edges())
	return said
