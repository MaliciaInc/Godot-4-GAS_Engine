## The menus the Composer opens, and what each one offers.
##
## Two lists, because a card and a pin are different things: the card's items are
## about the statement and the pin's are about the wires on it. Offering one list
## for both would put Remove in front of somebody who right-clicked a cable.
##
## It offers and reports, and does neither of the two things that matter: it does
## not decide whether the file may be written, and it does not perform anything.
## Both belong to the screen, which is why this can grow - TASK 12's catalog, a
## menu on the background - without any of that growth landing there.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerMenus extends Node

## What can be done to a statement.
const REMOVE: String = "Remove"
const REPEAT: String = "Repeat"
const COPY: String = "Copy"

## What can be done to a pin.
const FOR_CARD: Array[String] = [REMOVE, REPEAT, COPY]

## Which item was picked, and what it was opened on. The two travel together
## because the answer arrives long after the question.
signal chose(item: String, node_id: StringName, port_id: StringName)

## One exact cable is to come off, or every cable on one pin is.
##
## Passed straight up, the way every other menu answer is: what happens to the
## file is the screen's business and none of this file's.
signal break_link_requested(edge: ComposerGraph.Connection)
signal break_all_requested(node_id: StringName, port_id: StringName)

## Which call was picked out of the catalog, and what it is to be joined to.
signal entry_chosen(entry_key: StringName, context: ComposerActionMenu.Context)

var _card: ComposerCardMenu = null
var _pin: ComposerPinMenu = null
var _actions: ComposerActionMenu = null
var _document: ComposerDocument = null


func bind(document: ComposerDocument) -> void:
	_document = document


## Hear every request for a menu the canvas makes.
##
## Listening here rather than being wired up call by call, for the same reason
## the wiring routes do: a menu added to the canvas is connected beside the
## others instead of in a list somewhere else that has to be remembered.
func listen_to(canvas: ComposerCanvas) -> void:
	canvas.menu_requested.connect(_on_card_requested)
	canvas.pin_context_requested.connect(_on_pin_requested)
	canvas.graph_menu_requested.connect(_on_graph_requested)
	canvas.connection_to_empty_requested.connect(
		_on_dragged.bind(ComposerActionMenu.Context.Mode.FROM_PIN)
	)
	canvas.connection_from_empty_requested.connect(
		_on_dragged.bind(ComposerActionMenu.Context.Mode.TO_PIN)
	)


#region What the canvas asked for
func _on_card_requested(node_id: StringName, at: Vector2) -> void:
	if _may_write():
		open_for_card(node_id, at)


func _on_pin_requested(node_id: StringName, port_id: StringName, at: Vector2) -> void:
	if _may_write():
		open_for_pin(node_id, port_id, at)


## Right-click on the canvas itself: the whole catalog, nothing filtered out.
func _on_graph_requested(graph_position: Vector2, at: Vector2) -> void:
	var context: ComposerActionMenu.Context = ComposerActionMenu.Context.new()
	context.graph_position = graph_position
	_offer(context, at)


## A cable let go over nothing: what could go there, offered where the hand let
## go of it.
##
## One handler for both directions, told which way it went, because the two
## differ in nothing else. Both positions travel, and they are not
## interchangeable: the graph one is where on the canvas the card belongs, the
## screen one is where on the window the menu opens.
func _on_dragged(
	node_id: StringName,
	port_id: StringName,
	graph_position: Vector2,
	at: Vector2,
	mode: ComposerActionMenu.Context.Mode
) -> void:
	var context: ComposerActionMenu.Context = _context_for(node_id, port_id, mode)
	context.graph_position = graph_position
	_offer(context, at)


## What the pin carries, so the catalog can offer only what fits it.
func _context_for(
	node_id: StringName, port_id: StringName, mode: ComposerActionMenu.Context.Mode
) -> ComposerActionMenu.Context:
	var context: ComposerActionMenu.Context = ComposerActionMenu.Context.new()
	context.mode = mode
	context.node_id = node_id
	context.port_id = port_id
	var graph: ComposerGraph = _document.graph() if _may_write() else null
	var node: ComposerNode = graph.find_node(node_id) if graph != null else null
	var pin: ComposerNode.Port = node.find_port(port_id) if node != null else null
	if pin != null:
		context.kind = pin.kind
		context.type_name = pin.type_name
	return context


func _offer(context: ComposerActionMenu.Context, at: Vector2) -> void:
	if not _may_write():
		return
	if _actions == null:
		_actions = ComposerActionMenu.new()
		_actions.entry_chosen.connect(
			func _picked(key: StringName, chosen: ComposerActionMenu.Context) -> void:
				entry_chosen.emit(key, chosen)
		)
		add_child(_actions)
	_actions.open_for(context, at)


func _may_write() -> bool:
	return _document != null and _document.may_write()
#endregion


## Offer what can be done to a statement, where the pointer is.
func open_for_card(node_id: StringName, at: Vector2) -> void:
	_card = _ready_menu(_card, FOR_CARD)
	_card.open_at(at, node_id)


## Offer what can be done to the cables on a pin.
##
## Its own menu rather than the card's, because its entries are not a fixed list
## of names: one per cable actually on that pin, named for what it reaches.
func open_for_pin(node_id: StringName, port_id: StringName, at: Vector2) -> void:
	if _pin == null:
		_pin = ComposerPinMenu.new()
		_pin.break_link_requested.connect(
			func _one(edge: ComposerGraph.Connection) -> void:
				break_link_requested.emit(edge)
		)
		_pin.break_all_requested.connect(
			func _all(on_node: StringName, on_port: StringName) -> void:
				break_all_requested.emit(on_node, on_port)
		)
		add_child(_pin)
	_pin.open_for(_document.graph(), node_id, port_id, at)


## The menu, made the first time it is wanted.
##
## Made late rather than in `_ready`: a Composer nobody right-clicks never needs
## either of these, and a popup that exists is a window the editor has to keep.
func _ready_menu(menu: ComposerCardMenu, items: Array[String]) -> ComposerCardMenu:
	if menu != null:
		return menu
	var made: ComposerCardMenu = ComposerCardMenu.new()
	made.offer(items)
	made.chose.connect(
		func _picked(item: String, node_id: StringName, port_id: StringName) -> void:
			chose.emit(item, node_id, port_id)
	)
	add_child(made)
	return made
