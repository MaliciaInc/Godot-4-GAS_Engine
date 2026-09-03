## Where every node goes, worked out from the code rather than remembered.
##
## Nobody places a node. Under a code-canonical Composer a saved position has
## nowhere to live: it would either pollute the `.gd` that IS the truth with
## drawing metadata, or sit in a side file - a parallel truth wearing another
## name - or be lost on every open. Deriving it has none of those problems,
## because there is nothing to store.
##
## Returns grid coordinates, not pixels: `x` is the column, `y` is the lane.
## Cards are measured inside the tree a frame after they are placed, so a layout
## that dealt in pixels would need heights that do not exist yet. Keeping this
## side of the line free of geometry also keeps it a pure function - it is
## tested without opening a window.
##
## Two properties matter more than the shape it produces:
##
## - **Deterministic.** The same graph lays out the same way every time. If two
##   opens gave two drawings, nobody could recognise their own ability. Every
##   iteration here is over a sorted list for exactly that reason; a dictionary's
##   order is not a promise.
## - **Stable.** A local edit produces a local change. Appending a statement
##   cannot reshuffle what came before it, or the reader loses the map they had
##   in their head at the moment they most need it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerLayout extends RefCounted

const FIRST_COLUMN: int = 0
const FIRST_LANE: int = 0


## Column and lane for every node, keyed by node id.
static func arrange(graph: ComposerGraph) -> Dictionary[StringName, Vector2i]:
	var placements: Dictionary[StringName, Vector2i] = {}
	if graph == null or graph.nodes.is_empty():
		return placements

	var order: Array[StringName] = _sorted_ids(graph)
	var columns: Dictionary[StringName, int] = _columns(graph, order)
	var lanes: Dictionary[StringName, int] = _lanes(graph, order, columns)

	for id: StringName in order:
		placements[id] = Vector2i(columns[id], lanes[id])
	return placements


## Node ids, sorted. Every walk below starts from this so that nothing depends
## on the order the reader happened to append nodes in.
static func _sorted_ids(graph: ComposerGraph) -> Array[StringName]:
	var ids: Array[StringName] = []
	for node: ComposerNode in graph.nodes:
		ids.append(node.id)
	ids.sort_custom(_before)
	return ids


## Compare as text, never as StringName.
##
## `StringName` orders by its interned pointer rather than by its characters,
## which is fast and useless here: the order depends on which names the engine
## happened to intern first, so it holds within one session and changes in the
## next. A layout sorted that way is deterministic exactly long enough to pass a
## test that runs twice in a row, and lays a file out differently tomorrow.
static func _before(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)


#region Columns
## Longest path over execution edges.
##
## A node sits one column past the furthest thing that must run before it, so a
## branch's join lands after its longest side rather than beside its shortest.
## Reading left to right is reading the method top to bottom.
static func _columns(
	graph: ComposerGraph, order: Array[StringName]
) -> Dictionary[StringName, int]:
	var columns: Dictionary[StringName, int] = {}
	for id: StringName in order:
		columns[id] = FIRST_COLUMN

	# Bounded by the node count: a chain of N nodes settles in at most N passes,
	# and a cycle - which a statement sequence should never produce - stops here
	# instead of spinning.
	for _pass: int in order.size():
		var moved: bool = false
		for id: StringName in order:
			var deepest: int = FIRST_COLUMN
			for source: StringName in _execution_sources(graph, id):
				deepest = maxi(deepest, columns[source] + 1)
			if deepest != columns[id]:
				columns[id] = deepest
				moved = true
		if not moved:
			break
	return columns


## The nodes that must run before `id`, by execution edge, sorted.
static func _execution_sources(graph: ComposerGraph, id: StringName) -> Array[StringName]:
	var sources: Array[StringName] = []
	for wire: ComposerGraph.Connection in graph.connections:
		if wire.to_node != id or not _is_execution(graph, wire.from_node, wire.from_port):
			continue
		if not sources.has(wire.from_node):
			sources.append(wire.from_node)
	sources.sort_custom(_before)
	return sources


static func _is_execution(graph: ComposerGraph, node_id: StringName, port_id: StringName) -> bool:
	var node: ComposerNode = graph.find_node(node_id)
	if node == null:
		return false
	var port: ComposerNode.Port = node.find_port(port_id)
	return port != null and port.is_execution()
#endregion


#region Lanes
## Which row inside a column a node takes.
##
## The first successor of a node inherits its lane, so a straight sequence stays
## on one line and a branch is the only thing that opens a new one. That is what
## makes the main path visible as a path instead of a staircase.
static func _lanes(
	graph: ComposerGraph, order: Array[StringName], columns: Dictionary[StringName, int]
) -> Dictionary[StringName, int]:
	var lanes: Dictionary[StringName, int] = {}
	var taken: Dictionary[int, Array] = {}

	for id: StringName in _by_column(order, columns):
		var column: int = columns[id]
		if not taken.has(column):
			taken[column] = [] as Array[int]
		var used: Array = taken[column]

		var wanted: int = _inherited_lane(graph, id, lanes)
		while used.has(wanted):
			wanted += 1
		used.append(wanted)
		lanes[id] = wanted
	return lanes


## The lane of the first execution predecessor already placed, or the first lane
## when this node starts a path of its own.
static func _inherited_lane(
	graph: ComposerGraph, id: StringName, lanes: Dictionary[StringName, int]
) -> int:
	for source: StringName in _execution_sources(graph, id):
		if lanes.has(source):
			return lanes[source]
	return FIRST_LANE


## Ids ordered by column, then by id.
##
## Column order is what lets a node ask its predecessor for a lane and get an
## answer: everything to its left has already been placed.
static func _by_column(
	order: Array[StringName], columns: Dictionary[StringName, int]
) -> Array[StringName]:
	var sorted: Array[StringName] = order.duplicate()
	sorted.sort_custom(
		func _shallowest_first(left: StringName, right: StringName) -> bool:
			if columns[left] != columns[right]:
				return columns[left] < columns[right]
			return _before(left, right)
	)
	return sorted
#endregion
