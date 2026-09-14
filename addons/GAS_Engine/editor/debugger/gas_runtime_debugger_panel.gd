## What a running game says about its entities, drawn in the editor's Debugger
## dock: one tab per play session, beside Errors and Profiler.
##
## The in-game overlay's pages - the same GasDebugPage rows, put on screen by the
## same GasDebugTable - fed from what the game sent rather than from a
## component, because the component is in another process and what arrived in
## the log is all the editor knows. The entities down the side are every one the
## game is watching; the list under the table is what happened to the one
## chosen, newest first.
##
## Draws only when told to. The plugin decides when, because it is the one that
## knows a message arrived and which thread it arrived on.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GasRuntimeDebuggerPanel extends HSplitContainer

## The tab's title in the Debugger dock.
const TAB_TITLE: String = "GAS_Engine"
const NOTHING_YET: String = (
	"Nothing has reported yet. Every ability system reports here while the game runs from the editor."
)
const EVENTS_HEADING: String = "What happened, newest first"
const ENTITY_LIST_WIDTH: float = 180.0
const EVENTS_WIDTH: float = 360.0

## What this tab draws from: one session's log.
var reported: GasRuntimeDebuggerLog = null

var _pages: Array[GasDebugPage] = GasDebugCommands.pages()
var _showing: int = 0
var _selected: int = 0

var _entities: ItemList = null
var _nothing_yet: Label = null
var _tabs: HBoxContainer = null
var _table: Tree = null
var _events: ItemList = null


func _init(from: GasRuntimeDebuggerLog = null) -> void:
	name = TAB_TITLE
	reported = from if from != null else GasRuntimeDebuggerLog.new()
	_build()


#region What is shown
## Draw everything again from the log.
func refresh() -> void:
	var ids: Array[int] = reported.watched_ids()
	if not ids.has(_selected):
		_selected = ids[0] if not ids.is_empty() else 0
	_nothing_yet.visible = ids.is_empty()
	_show_entities(ids)
	GasDebugTable.draw(
		_table, _pages[_showing], reported.snapshot(_selected), _notable(), _ordinary()
	)
	_show_events()


## Show one entity. False when the game has said nothing about it.
func select(asc_id: int) -> bool:
	if reported.snapshot(asc_id) == null:
		return false
	_selected = asc_id
	refresh()
	return true


## Show one page, by its position in `pages()`. Out of range is refused rather
## than clamped, for the reason the overlay gives.
func show_page(index: int) -> bool:
	if index < 0 or index >= _pages.size():
		return false
	_showing = index
	refresh()
	return true


func pages() -> Array[GasDebugPage]:
	return _pages


func showing() -> int:
	return _showing


## The entity on screen, by instance id, or 0 when there is none.
func selected() -> int:
	return _selected


func table() -> Tree:
	return _table


## The entities listed, as they are listed.
func entity_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for index: int in _entities.item_count:
		names.append(_entities.get_item_text(index))
	return names


## What happened to the chosen entity, as it is listed.
func event_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for index: int in _events.item_count:
		lines.append(_events.get_item_text(index))
	return lines
#endregion


#region Drawing
func _show_entities(ids: Array[int]) -> void:
	_entities.clear()
	for asc_id: int in ids:
		var index: int = _entities.add_item(GasDebugTable.named(reported.snapshot(asc_id)))
		_entities.set_item_metadata(index, asc_id)
		if asc_id == _selected:
			_entities.select(index)


func _show_events() -> void:
	_events.clear()
	var happened: Array[GasTraceEvent] = reported.events_for(_selected)
	for index: int in range(happened.size() - 1, -1, -1):
		_events.add_item(happened[index].described())


## Coloured by the editor's own theme, which this tab stands inside - a colour
## chosen here would be right against one editor theme and wrong against the next.
func _notable() -> Color:
	return get_theme_color(GASEditorTheme.WARNING_COLOR, GASEditorTheme.EDITOR_THEME_TYPE)


func _ordinary() -> Color:
	return get_theme_color(GASEditorTheme.FONT_COLOR, GASEditorTheme.EDITOR_THEME_TYPE)


func _on_entity_chosen(index: int) -> void:
	var asc_id: int = _entities.get_item_metadata(index)
	select(asc_id)
#endregion


#region Building the shell
func _build() -> void:
	_entities = ItemList.new()
	_entities.custom_minimum_size.x = ENTITY_LIST_WIDTH
	_entities.item_selected.connect(_on_entity_chosen)
	add_child(_entities)

	# The page beside what happened rather than above it. The Debugger dock is
	# wide and short, and stacked the two shared its height: measured in a real
	# editor, the table had room for two rows.
	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(body)

	var page: VBoxContainer = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nothing_yet = Label.new()
	_nothing_yet.text = NOTHING_YET
	page.add_child(_nothing_yet)
	_tabs = HBoxContainer.new()
	GasDebugTable.build_tabs(_tabs, _pages, show_page)
	page.add_child(_tabs)
	_table = Tree.new()
	_table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_table)
	body.add_child(page)

	var happened: VBoxContainer = VBoxContainer.new()
	happened.custom_minimum_size.x = EVENTS_WIDTH
	var heading: Label = Label.new()
	heading.text = EVENTS_HEADING
	happened.add_child(heading)
	_events = ItemList.new()
	_events.size_flags_vertical = Control.SIZE_EXPAND_FILL
	happened.add_child(_events)
	body.add_child(happened)
#endregion
