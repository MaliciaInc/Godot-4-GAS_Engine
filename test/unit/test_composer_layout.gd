## Auto-layout: where a node goes, worked out rather than remembered.
##
## Two of these tests matter more than the rest. One lays the same structure out
## twice from lists built in opposite orders and demands the same answer; the
## other appends a node and demands that nothing before it moved. A layout that
## fails either is unusable no matter how good the arrangement looks: the first
## means a person cannot recognise their own ability between two opens, and the
## second means every edit throws away the map they had in their head.
##
## @meta_license: MIT
extends GutTest

const PORT_IN: StringName = &"exec_in"
const PORT_OUT: StringName = &"exec_out"
const PORT_ALT: StringName = &"exec_else"
const PORT_VALUE: StringName = &"value"


#region Building graphs
func _exec_port(id: StringName, direction: ComposerNode.PortDirection) -> ComposerNode.Port:
	var port: ComposerNode.Port = ComposerNode.Port.new()
	port.id = id
	port.kind = ComposerNode.PortKind.EXECUTION
	port.direction = direction
	return port


func _node(id: StringName) -> ComposerNode:
	var node: ComposerNode = ComposerNode.new()
	node.id = id
	node.ports = [
		_exec_port(PORT_IN, ComposerNode.PortDirection.INPUT),
		_exec_port(PORT_OUT, ComposerNode.PortDirection.OUTPUT),
		_exec_port(PORT_ALT, ComposerNode.PortDirection.OUTPUT),
	] as Array[ComposerNode.Port]
	return node


## A data port carries no execution, so nothing downstream of it moves a column.
func _data_only(id: StringName) -> ComposerNode:
	var node: ComposerNode = ComposerNode.new()
	node.id = id
	var port: ComposerNode.Port = ComposerNode.Port.new()
	port.id = PORT_VALUE
	port.kind = ComposerNode.PortKind.DATA
	port.direction = ComposerNode.PortDirection.OUTPUT
	node.ports = [port] as Array[ComposerNode.Port]
	return node


func _wire(
	source: StringName, source_port: StringName, target: StringName
) -> ComposerGraph.Connection:
	var wire: ComposerGraph.Connection = ComposerGraph.Connection.new()
	wire.from_node = source
	wire.from_port = source_port
	wire.to_node = target
	wire.to_port = PORT_IN
	return wire


func _graph(nodes: Array, wires: Array) -> ComposerGraph:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.nodes.assign(nodes)
	graph.connections.assign(wires)
	return graph
#endregion


#region Shape
## A sequence reads as a line, and only a branch opens a second lane.
##
## Both halves are here together because they are one rule seen twice: the first
## successor inherits its predecessor's lane. Without that a plain sequence would
## descend like a staircase and the main path would stop looking like a path.
func test_a_sequence_holds_one_lane_and_a_branch_opens_the_next() -> void:
	var line: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(_graph(
		[_node(&"a"), _node(&"b"), _node(&"c")],
		[_wire(&"a", PORT_OUT, &"b"), _wire(&"b", PORT_OUT, &"c")]
	))
	assert_eq(line[&"a"], Vector2i(0, 0), "the entry starts at the origin")
	assert_eq(line[&"b"], Vector2i(1, 0), "one column along, same lane")
	assert_eq(line[&"c"], Vector2i(2, 0), "and again - a sequence reads as a line")

	var fork: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(_graph(
		[_node(&"a"), _node(&"b"), _node(&"c")],
		[_wire(&"a", PORT_OUT, &"b"), _wire(&"a", PORT_ALT, &"c")]
	))
	assert_eq(fork[&"b"], Vector2i(1, 0), "one side leaves the branch holding the lane")
	assert_eq(fork[&"c"], Vector2i(1, 1), "and the other takes the next")


## Longest path, not shortest: a join must sit past everything that has to run
## before it, or a wire would point backwards.
func test_a_join_lands_past_the_longest_side_of_the_branch() -> void:
	var placed: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(_graph(
		[_node(&"a"), _node(&"b"), _node(&"c"), _node(&"d"), _node(&"join")],
		[
			_wire(&"a", PORT_OUT, &"b"), _wire(&"b", PORT_OUT, &"c"),
			_wire(&"a", PORT_ALT, &"d"),
			_wire(&"c", PORT_OUT, &"join"), _wire(&"d", PORT_OUT, &"join"),
		]
	))

	assert_eq(placed[&"c"].x, 2, "the long side reaches column two")
	assert_eq(placed[&"d"].x, 1, "the short side stops at one")
	assert_eq(placed[&"join"].x, 3, "and the join clears the long side, not the short one")


func test_a_node_wired_only_by_data_does_not_advance_a_column() -> void:
	var placed: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(_graph(
		[_node(&"a"), _data_only(&"value")], [_wire(&"value", PORT_VALUE, &"a")]
	))

	assert_eq(
		placed[&"a"].x, 0,
		"a data wire says what depends on what, and nothing about when"
	)
#endregion


#region Determinism
## The strongest statement this suite can make: structure decides the layout,
## and the order the reader happened to append nodes in decides nothing.
##
## Anything iterating a Dictionary directly would pass the repeat-run test below
## and fail this one, which is why both are here.
func test_the_same_structure_laid_out_from_opposite_orders_agrees() -> void:
	var wires: Array = [_wire(&"a", PORT_OUT, &"b"), _wire(&"b", PORT_OUT, &"c")]
	var forward: ComposerGraph = _graph([_node(&"a"), _node(&"b"), _node(&"c")], wires)
	var backward: ComposerGraph = _graph([_node(&"c"), _node(&"b"), _node(&"a")], wires)

	assert_eq(
		ComposerLayout.arrange(forward), ComposerLayout.arrange(backward),
		"appending in reverse is still the same ability"
	)


func test_laying_the_same_graph_out_twice_gives_the_same_answer() -> void:
	var graph: ComposerGraph = _graph(
		[_node(&"a"), _node(&"b"), _node(&"c")],
		[_wire(&"a", PORT_OUT, &"b"), _wire(&"a", PORT_ALT, &"c")]
	)

	assert_eq(
		ComposerLayout.arrange(graph), ComposerLayout.arrange(graph),
		"two opens of one file draw the same picture"
	)
#endregion


#region Stability
## A local edit is a local change.
##
## Appending a statement is the most common edit there is. If it reshuffled the
## nodes above it, every edit would cost the reader the map they already had.
func test_appending_a_statement_moves_nothing_before_it() -> void:
	var grown: Array = [_wire(&"a", PORT_OUT, &"b"), _wire(&"a", PORT_ALT, &"c")]
	var was: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(
		_graph([_node(&"a"), _node(&"b"), _node(&"c")], grown)
	)
	var now: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(_graph(
		[_node(&"a"), _node(&"b"), _node(&"c"), _node(&"d")],
		grown + [_wire(&"b", PORT_OUT, &"d")]
	))

	for id: StringName in [&"a", &"b", &"c"] as Array[StringName]:
		assert_eq(now[id], was[id], "%s stayed where it was" % id)
	assert_eq(now[&"d"], Vector2i(2, 0), "only the new statement is new")
#endregion


#region Refusing to hang
## A statement sequence cannot loop, but a reader with a bug could hand one over
## and an unbounded relaxation would spin on it forever. Bounded by the node
## count, it stops with an answer instead of freezing the editor.
func test_a_cycle_terminates_instead_of_spinning() -> void:
	var graph: ComposerGraph = _graph(
		[_node(&"a"), _node(&"b")],
		[_wire(&"a", PORT_OUT, &"b"), _wire(&"b", PORT_OUT, &"a")]
	)

	var placed: Dictionary[StringName, Vector2i] = ComposerLayout.arrange(graph)
	assert_eq(placed.size(), 2, "both nodes came back")


func test_an_empty_graph_places_nothing() -> void:
	assert_eq(ComposerLayout.arrange(ComposerGraph.new()).size(), 0, "nothing to place")
	assert_eq(ComposerLayout.arrange(null).size(), 0, "and null is not a crash")
#endregion
