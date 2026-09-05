## Cutting one execution link, and joining one, by the pin it leaves.
##
## There is no single rule for this. Taking the link off an ordinary statement's
## way out means the run below it stops being reached; taking it off a branch's
## True means that path is left leading nowhere while the false side carries on
## exactly as it did; taking it off a match's No Match means writing down the
## catch-all the file never had. One reachability heuristic for all of them draws
## a graph that is not the file - which is what sections 62 and 63 freeze against
## by giving each pin its own handler.
##
## Every handler answers in the same shape: the text this would produce, or
## nothing when this pin cannot express it. Nothing here decides whether the
## operation is allowed and nothing here commits: `ComposerFlowEdits` drives
## these one link at a time and proves afterwards that the file says what was
## asked for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerFlowPaths extends RefCounted

const NEWLINE: String = "\n"


#region Cutting one link
## The text with that link gone, or nothing when this pin cannot express it.
static func disconnect_once(
	source: String, graph: ComposerGraph, edge: ComposerGraph.Connection
) -> String:
	var from: ComposerNode = graph.find_node(edge.from_node)
	if from == null:
		return ""
	if edge.from_port == ComposerReader.EXEC_OUT:
		return _cut_ordinary(source, graph, edge)
	if edge.from_port == ComposerReader.TRUE_OUT:
		return _cut_body(source, graph, from)
	if edge.from_port == ComposerReader.FALSE_OUT:
		return _cut_false(source, graph, from)
	if edge.from_port == ComposerReader.UNMATCHED_OUT:
		return _cut_unmatched(source, graph, from)
	return _cut_case(source, graph, from, edge.from_port)


## The ordinary way out: whatever stops being reached is set aside, marked, and
## the shortened path is given somewhere to end.
##
## Refused rather than approximated when the statements that stop being reached
## are not one run of lines: a wrapper drawn round a gap would swallow a
## statement that is still supposed to run.
static func _cut_ordinary(
	source: String, graph: ComposerGraph, edge: ComposerGraph.Connection
) -> String:
	var stranded: Array[ComposerNode] = ComposerFlow.stranded_by(graph, edge)
	if stranded.is_empty():
		return ""
	var region: ComposerSpan = ComposerFlowText.region_of(stranded)
	if not ComposerFlowText.is_contiguous(stranded, region):
		return ""

	var wrapped: PackedStringArray = ComposerFlowText.detached(
		source.split(NEWLINE), region
	)
	return ComposerFlowText.ended(NEWLINE.join(wrapped), region.first_line)


## A structural path with a body of its own: the body is set aside and the path
## ends where it was.
##
## `header` is the line the path leaves from - the branch itself for its true
## side, the `else` or the arm for the others.
static func _cut_body(source: String, graph: ComposerGraph, header: ComposerNode) -> String:
	var region: ComposerSpan = ComposerFlowPlaces.body_of(graph, header)
	if not region.is_valid():
		return ""
	return ComposerFlowTransforms.stopped_path(source, region, header.indent + 1)


## The false path, which is written three different ways and cut three ways.
static func _cut_false(
	source: String, graph: ComposerGraph, branch: ComposerNode
) -> String:
	var otherwise: ComposerNode = ComposerFlowPlaces.else_of(graph, branch)
	if otherwise != null:
		return _cut_body(source, graph, otherwise)
	if ComposerFlowPlaces.chains_on(graph, branch):
		# `elif b:` *is* the false path, so there is nothing to set aside until
		# the chain is written out long. Section 62.5: normalise only the chain
		# being cut, then cut the nested else that now exists.
		var nested: String = ComposerFlowTransforms.with_nested_else(
			source, graph, branch, ""
		)
		var read: ComposerGraph = ComposerReader.read(nested, graph.source_path)
		if not read.is_editable():
			return ""
		var again: ComposerNode = read.node_at_line(branch.span.last_line)
		if again == null:
			return ""
		return _cut_false(nested, read, again)
	# It falls straight through to whatever follows the block, so the boundary
	# that would stop it does not exist yet and is written.
	return ComposerFlowTransforms.with_else_stop(source, graph, branch)


## One arm of a match.
static func _cut_case(
	source: String, graph: ComposerGraph, switch: ComposerNode, port_id: StringName
) -> String:
	var arm: ComposerNode = ComposerFlowPlaces.case_of(graph, switch, port_id)
	if arm == null:
		return ""
	return _cut_body(source, graph, arm)


## The path a match takes when none of its arms match.
static func _cut_unmatched(
	source: String, graph: ComposerGraph, switch: ComposerNode
) -> String:
	var wildcard: ComposerNode = ComposerFlowPlaces.wildcard_of(graph, switch)
	if wildcard != null:
		return _cut_body(source, graph, wildcard)
	return ComposerFlowTransforms.with_default_stop(source, graph, switch)
#endregion


#region Joining one link
## The text with that link made, or nothing when this pin cannot express it.
##
## What may be joined is narrow on purpose: the statement being joined to has to
## be a block somebody set aside, because that is the only thing in a file that
## is a run of statements with nowhere to run from. Anything else would be a
## jump, and a jump is not something GDScript can say.
static func connect_once(
	source: String, graph: ComposerGraph, edge: ComposerGraph.Connection
) -> String:
	var from: ComposerNode = graph.find_node(edge.from_node)
	var to: ComposerNode = graph.find_node(edge.to_node)
	if from == null or to == null or from.terminal:
		return ""
	var island: String = ComposerFlowPlaces.island_of(graph, to)
	if island.is_empty():
		return ""

	var anchor: ComposerFlowPlaces.Anchor = ComposerFlowPlaces.anchor_for(
		graph, from, edge.from_port
	)
	if not anchor.is_ok():
		return ""

	var written: String = ComposerFlowTransforms.released_into(source, island, anchor)
	if written.is_empty():
		return ""
	return _tidied(written, graph.source_path)


## Take out the machinery the cut left behind, and give back what is now real.
##
## Three things, in this order: a stop nothing reaches any more is gone, a
## boundary this tool wrote that is now empty goes with it, and a boundary that
## has ended up holding what somebody asked for stops being marked as ours -
## because from here on it is theirs, and cleanup must never take it away.
static func _tidied(source: String, path: String) -> String:
	var written: String = ComposerFlowText.spent_stops_removed(source, path)
	for mark: String in [
		ComposerSubset.FLOW_ELSE_MARK, ComposerSubset.FLOW_DEFAULT_MARK
	]:
		written = ComposerFlowTransforms.spent_boundaries_removed(written, mark)
		written = ComposerFlowTransforms.unmarked(written, mark)
	return written
#endregion
