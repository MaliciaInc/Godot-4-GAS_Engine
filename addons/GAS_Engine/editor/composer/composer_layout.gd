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
## @meta_license: GAS_Engine Community Use License 1.0
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
## Grid coordinates become pixels, each column as wide as its widest card.
##
## A fixed step assumed every card had one width. They do not: a card is as wide
## as the longest thing it has to say, so a column holding a wide one has to be
## wider or the next column lands on top of it.
##
## `widths` is allowed to be short, and is on the first pass - a card has no
## measured size until a frame has gone by. What is missing counts as the
## minimum, and the second pass, once every card has been fitted, uses what they
## turned out to be.
static func origins(
	placements: Dictionary[StringName, Vector2i],
	widths: Dictionary[StringName, float] = {},
	heights: Dictionary[StringName, float] = {}
) -> Dictionary[StringName, Vector2]:
	var starts: Dictionary[int, float] = _offsets(
		_extents(placements, widths, true), ComposerTheme.COLUMN_GAP
	)

	var tops: Dictionary[int, float] = _offsets(
		_extents(placements, heights, false), ComposerTheme.LANE_GAP
	)

	var found: Dictionary[StringName, Vector2] = {}
	for id: StringName in placements:
		var at: Vector2i = placements[id]
		found[id] = Vector2(starts[at.x], tops[at.y])
	return found


## The largest card in each column, or in each lane.
##
## One walk for both axes: a column is as wide as its widest card and a lane is
## as tall as its tallest, which is the same question asked twice. Written once
## because the horizontal half was written first and the vertical half was not,
## and a graph whose lanes overlapped is what that cost.
## Put every card where the layout wants it, now that they have been measured.
##
## The second pass, and the one that needs real sizes: the first could only guess
## from a minimum, and a column is only as wide as what it turned out to hold.
##
## A card somebody moved themselves keeps where they put it. Overruling that on
## every redraw would move their graph back under them each time they edited a
## field - which is the whole reason a placement is written into the file.
static func settle(
	cards: Dictionary[StringName, ComposerCard],
	placements: Dictionary[StringName, Vector2i],
	graph: ComposerGraph
) -> void:
	var widths: Dictionary[StringName, float] = {}
	var heights: Dictionary[StringName, float] = {}
	for id: StringName in cards:
		widths[id] = cards[id].size.x
		heights[id] = cards[id].size.y

	var placed: Dictionary[StringName, Vector2] = origins(placements, widths, heights)
	for id: StringName in cards:
		var model: ComposerNode = graph.find_node(id)
		if model != null and not model.has_layout_position and placed.has(id):
			cards[id].position_offset = placed[id]


static func _extents(
	placements: Dictionary[StringName, Vector2i],
	sizes: Dictionary[StringName, float],
	across: bool
) -> Dictionary[int, float]:
	var largest: Dictionary[int, float] = {}
	for id: StringName in placements:
		var slot: int = placements[id].x if across else placements[id].y
		var span: float = sizes[id] if sizes.has(id) else _least(across)
		largest[slot] = maxf(largest[slot] if largest.has(slot) else 0.0, span)
	return largest


## What an unmeasured card counts as. Cards have no size until a frame has gone
## by, so the first placement guesses and the second, once they are fitted, does
## not have to.
static func _least(across: bool) -> float:
	return ComposerTheme.NODE_MIN_WIDTH if across else ComposerTheme.NODE_MIN_HEIGHT


## Where each slot starts, laid end to end with a gap between them.
static func _offsets(largest: Dictionary[int, float], gap: float) -> Dictionary[int, float]:
	var slots: Array[int] = []
	slots.assign(largest.keys())
	slots.sort()

	var starts: Dictionary[int, float] = {}
	var running: float = 0.0
	for slot: int in slots:
		starts[slot] = running
		running += largest[slot] + gap
	return starts


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
