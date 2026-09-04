## The catalog, offered where somebody asked for it.
##
## Opened three ways, and the difference between them is the whole point. From
## nothing, it offers everything. Dragged out of a pin and let go over empty
## canvas, it offers only what could actually be joined to that pin - so the list
## a person reads is the list of things that will work.
##
## Nothing incompatible is ever shown and then refused after it is picked. A menu
## that offers a choice it will not honour teaches people to distrust the menu,
## and they stop reading it and go back to typing GDScript.
##
## The search runs after the compatibility filter, never instead of it: typing
## narrows what is offered and cannot widen it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerActionMenu extends PopupPanel

const WIDTH: float = 320.0
const HEIGHT: float = 360.0
const SEARCH_HINT: String = "Search calls"


## Where the menu was opened, and what it therefore may offer.
##
## Carried as one value rather than five arguments: every one of them is needed
## to answer "what fits here", and a caller that passed four of them would get an
## answer to a different question.
class Context extends RefCounted:
	enum Mode { ALL, FROM_PIN, TO_PIN }

	var mode: ComposerActionMenu.Context.Mode = ComposerActionMenu.Context.Mode.ALL
	var node_id: StringName = &""
	var port_id: StringName = &""
	var graph_position: Vector2 = Vector2.ZERO
	var kind: ComposerNode.PortKind = ComposerNode.PortKind.EXECUTION
	var type_name: StringName = &""

	func is_execution() -> bool:
		return kind == ComposerNode.PortKind.EXECUTION


## Which call was picked, and what it is being joined to.
##
## The context travels with the answer because the answer arrives long after the
## question: a menu is open while somebody reads it, and a caller holding "which
## pin was that" in a field of its own has a field that is stale the moment a
## second menu opens.
signal entry_chosen(entry_key: StringName, context: ComposerActionMenu.Context)

var _context: ComposerActionMenu.Context = ComposerActionMenu.Context.new()
var _offered: Array[ComposerCatalog.Entry] = []
var _search: LineEdit = null
var _list: ItemList = null


#region What fits here
## The calls this context may offer, before any search narrows them.
##
## The graph is not consulted. Everything the question needs is in the context -
## which way the pin faces, what it carries - and reaching for the graph as well
## would be two sources for one answer.
static func compatible_entries(
	context: ComposerActionMenu.Context
) -> Array[ComposerCatalog.Entry]:
	var offered: Array[ComposerCatalog.Entry] = []
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		if _fits(context, entry):
			offered.append(entry)
	# Sorted by the words a person reads, so the same context always offers the
	# same list in the same order however the catalog was built.
	offered.sort_custom(
		func _by_title(one: ComposerCatalog.Entry, other: ComposerCatalog.Entry) -> bool:
			return one.title < other.title
	)
	return offered


static func _fits(
	context: ComposerActionMenu.Context, entry: ComposerCatalog.Entry
) -> bool:
	if context.mode == ComposerActionMenu.Context.Mode.ALL:
		return true
	# Every call in the catalog becomes a statement, and a statement is something
	# execution can arrive at and leave. So a run of control fits all of them.
	if context.is_execution():
		return true
	if context.mode == ComposerActionMenu.Context.Mode.FROM_PIN:
		return first_argument_for(context, entry) >= 0
	return _hands_back(context, entry)


## Which argument of `entry` a value of the context's type would go into, or -1.
##
## The first that accepts it, in the order the method declares them. First rather
## than best: a person dragging a value into a call means "put it where it goes",
## and there is no second guess to make - but the choice has to be the same every
## time, or the same drag lands in different arguments on different days.
static func first_argument_for(
	context: ComposerActionMenu.Context, entry: ComposerCatalog.Entry
) -> int:
	for position: int in entry.parameters.size():
		if ComposerTypes.accepts(entry.parameters[position].type_name, context.type_name):
			return position
	return -1


## Whether the entry hands back something that argument could hold.
##
## A call that suspends is left out: its result is a task to wait on, not a value
## to pass, and offering one here would write `var x = await ...` into an
## argument as though the two were the same thing.
static func _hands_back(
	context: ComposerActionMenu.Context, entry: ComposerCatalog.Entry
) -> bool:
	if not ComposerTypes.is_a_value(entry.result_type) or entry.awaits:
		return false
	return ComposerTypes.accepts(context.type_name, entry.result_type)


## What is offered once the search has been applied too.
##
## After the compatibility filter, never instead of it. Typing narrows the list
## and cannot widen it, so nothing incompatible can be reached by spelling it.
static func matching(
	offered: Array[ComposerCatalog.Entry], written: String
) -> Array[ComposerCatalog.Entry]:
	var wanted: String = written.strip_edges().to_lower()
	if wanted.is_empty():
		return offered
	var found: Array[ComposerCatalog.Entry] = []
	for entry: ComposerCatalog.Entry in offered:
		if entry.title.to_lower().contains(wanted) or String(entry.type_id).to_lower().contains(wanted):
			found.append(entry)
	return found
#endregion


#region Opening it
func _ready() -> void:
	size = Vector2(WIDTH, HEIGHT)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(column)

	_search = LineEdit.new()
	_search.placeholder_text = SEARCH_HINT
	_search.text_changed.connect(func _typed(_text: String) -> void: _redraw_list())
	_search.gui_input.connect(_on_search_input)
	column.add_child(_search)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_on_item_activated)
	column.add_child(_list)


## Offer what fits `context`, at a point in the viewport.
func open_for(
	context: ComposerActionMenu.Context, screen_position: Vector2
) -> void:
	_context = context
	_offered = compatible_entries(context)
	if _search != null:
		_search.text = ""
	_redraw_list()
	position = Vector2i(screen_position)
	popup()
	if _search != null:
		_search.grab_focus()


func _redraw_list() -> void:
	if _list == null:
		return
	_list.clear()
	for entry: ComposerCatalog.Entry in _shown():
		_list.add_item(entry.title)
	if _list.item_count > 0:
		_list.select(0)


func _shown() -> Array[ComposerCatalog.Entry]:
	return matching(_offered, _search.text if _search != null else "")
#endregion


#region Choosing one
## Up and down move through the list, Enter takes one, Escape closes.
##
## Handled on the search box because that is where the caret is: a person opens
## this and types, and keys that only worked once they had clicked the list would
## be keys nobody finds.
func _on_search_input(event: InputEvent) -> void:
	if event.is_action_pressed(ComposerKeys.CANCEL):
		hide()
		_search.accept_event()
		return
	if event.is_action_pressed(ComposerKeys.DOWN):
		_step(1)
		return
	if event.is_action_pressed(ComposerKeys.UP):
		_step(-1)
		return
	if event.is_action_pressed(ComposerKeys.ACCEPT) or event.is_action_pressed(ComposerKeys.SUBMIT):
		_choose(_list.get_selected_items()[0] if _list.is_anything_selected() else 0)


func _step(by: int) -> void:
	if _list.item_count == 0:
		return
	var at: int = _list.get_selected_items()[0] if _list.is_anything_selected() else 0
	_list.select(clampi(at + by, 0, _list.item_count - 1))
	_search.accept_event()


func _on_item_activated(index: int) -> void:
	_choose(index)


func _choose(index: int) -> void:
	var shown: Array[ComposerCatalog.Entry] = _shown()
	if index < 0 or index >= shown.size():
		return
	hide()
	entry_chosen.emit(shown[index].key, _context)
#endregion
