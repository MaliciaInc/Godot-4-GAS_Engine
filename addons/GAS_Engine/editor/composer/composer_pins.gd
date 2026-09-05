## Which pin is under a pointer.
##
## One question, asked by every gesture that means something to a wire: Alt-click
## to clear a pin, Ctrl-drag to move what is on one, right-click to ask what can
## be done to it. Kept apart from the canvas because the canvas draws a graph and
## this reads a point, and the arithmetic is the part that is easy to get subtly
## wrong - a pin found one row off looks exactly like a pin found correctly until
## somebody's cable moves.
##
## The arithmetic, measured rather than assumed: GraphNode reports a port's place
## in the card's own unscaled space, and the card is drawn at `position` - which
## already carries the scroll and the zoom - with everything on it scaled by the
## zoom. So a pin sits at `card.position + port * zoom`.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerPins extends RefCounted

## How near a pointer has to be to a pin to have meant it, in graph units. Scaled
## with everything else, because a person aims at the drawn dot and the dot
## scales too.
const REACH: float = 12.0


## A pin, once one has been found.
##
## Which side it is on is carried rather than worked out later: an input and an
## output can sit at the same height on two cards, and a gesture that lost that
## would move wires between pins facing the same way.
class Pin extends RefCounted:
	var node_id: StringName = &""
	var port_id: StringName = &""
	var is_output: bool = false

	func is_found() -> bool:
		return not port_id.is_empty()

	## Whether this is the very same pin as `other`, rather than one like it.
	func is_same_as(other: ComposerPins.Pin) -> bool:
		return node_id == other.node_id and port_id == other.port_id


## The pin nearest `at`, within reach, or one that was not found.
##
## Nearest rather than first: two pins can both be within reach at a low zoom,
## and taking whichever card happened to be earlier in the dictionary would make
## the gesture depend on the order the graph was read in.
static func at(
	cards: Dictionary[StringName, ComposerCard], zoom: float, point: Vector2
) -> ComposerPins.Pin:
	var found: ComposerPins.Pin = ComposerPins.Pin.new()
	var nearest: float = REACH * zoom
	for id: StringName in cards:
		var card: ComposerCard = cards[id]
		for outgoing: bool in [false, true]:
			var closest: ComposerPins.Pin = _on_side(card, id, outgoing, zoom, point)
			if closest.port_id.is_empty():
				continue
			var reach: float = point.distance_to(_place_of(card, closest, zoom))
			if reach > nearest:
				continue
			nearest = reach
			found = closest
	return found


## The nearest pin on one side of one card, ignoring how far it is.
static func _on_side(
	card: ComposerCard, id: StringName, outgoing: bool, zoom: float, point: Vector2
) -> ComposerPins.Pin:
	var found: ComposerPins.Pin = ComposerPins.Pin.new()
	var nearest: float = INF
	var count: int = (
		card.get_output_port_count() if outgoing else card.get_input_port_count()
	)
	for index: int in count:
		var local: Vector2 = (
			card.get_output_port_position(index) if outgoing
			else card.get_input_port_position(index)
		)
		var reach: float = point.distance_to(_drawn_at(card, local, zoom))
		if reach >= nearest:
			continue
		nearest = reach
		found.node_id = id
		found.is_output = outgoing
		found.port_id = (
			card.right_port_of_drawn(index) if outgoing
			else card.left_port_of_drawn(index)
		)
	return found


## Where a found pin is drawn, in the canvas's own coordinates.
static func _place_of(
	card: ComposerCard, pin: ComposerPins.Pin, zoom: float
) -> Vector2:
	var index: int = (
		card.right_index_for_port(pin.port_id) if pin.is_output
		else card.left_index_for_port(pin.port_id)
	)
	if index < 0:
		return card.position
	var local: Vector2 = (
		card.get_output_port_position(index) if pin.is_output
		else card.get_input_port_position(index)
	)
	return _drawn_at(card, local, zoom)


## Where a pin drawn at `local` on that card is, in the coordinates the
## caller is asking in.
##
## The card's own position is included at canvas scale and left out at card
## scale, which is the whole difference between the two questions.
static func _drawn_at(card: ComposerCard, local: Vector2, zoom: float) -> Vector2:
	return card.position + local * zoom


#region What a drawn index means
## The semantic port a drawn index stands for on one card, or nothing.
static func port_of(
	cards: Dictionary[StringName, ComposerCard],
	node_id: StringName,
	index: int,
	outgoing: bool
) -> StringName:
	if not cards.has(node_id):
		return &""
	var card: ComposerCard = cards[node_id]
	return card.right_port_of_drawn(index) if outgoing else card.left_port_of_drawn(index)


## Which drawn pin on that card a semantic port is, or -1.
static func drawn_index(
	cards: Dictionary[StringName, ComposerCard],
	node_id: StringName,
	port_id: StringName,
	outgoing: bool
) -> int:
	if not cards.has(node_id):
		return -1
	var card: ComposerCard = cards[node_id]
	return (
		card.right_index_for_port(port_id) if outgoing
		else card.left_index_for_port(port_id)
	)


## Two drawn pin numbers as the connection they stand for, or nothing.
##
## Nothing when either end cannot be named. The widget's numbering is its own,
## and a request carrying a port id nobody recognises would be answered with a
## refusal about a pin the person never touched.
static func edge_of(
	cards: Dictionary[StringName, ComposerCard],
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> ComposerGraph.Connection:
	var out: StringName = port_of(cards, from_node, from_port, true)
	var into: StringName = port_of(cards, to_node, to_port, false)
	if out.is_empty() or into.is_empty():
		return null
	return ComposerReader.wire(from_node, out, to_node, into)
#endregion
