## One page of the runtime debugger drawn into a Tree, and the tabs that choose it.
##
## Written once for both surfaces that draw pages - the overlay inside a running
## game and the tab in the editor's Debugger dock - so the two cannot drift into
## drawing one entity two ways. What a row says is the page's; this only puts it
## on screen.
##
## Under `debug/` rather than `editor/`, because the running game draws with it:
## a game must name nothing under `editor/`, and the editor may use anything here.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugTable extends RefCounted


## Clear `table` and draw one page of one snapshot into it.
##
## The headings are drawn even without a snapshot, so a surface with nothing to
## show still says what it would show.
static func draw(
	table: Tree, page: GasDebugPage, snapshot: GasRuntimeSnapshot, notable: Color, ordinary: Color
) -> void:
	table.clear()
	if page == null:
		return

	var headings: PackedStringArray = page.columns()
	table.columns = maxi(headings.size(), 1)
	table.hide_root = true
	for column: int in headings.size():
		table.set_column_title(column, headings[column])
	table.column_titles_visible = true

	var root: TreeItem = table.create_item()
	if snapshot == null:
		return
	for row: GasDebugPage.Row in page.rows(snapshot):
		_draw_row(table, root, row, notable if row.notable else ordinary)


static func _draw_row(table: Tree, under: TreeItem, row: GasDebugPage.Row, color: Color) -> void:
	var item: TreeItem = table.create_item(under)
	# The whole line as the tooltip of every cell: a debugger gets whatever width
	# is left beside the game or the editor, so a column wide enough for
	# `Status.Stunned` is not wide enough for the effect that granted it.
	var whole: String = row.said()
	for column: int in row.cells.size():
		if column >= table.columns:
			break
		item.set_text(column, row.cells[column])
		item.set_tooltip_text(column, whole)
		item.set_custom_color(column, color)


## One button per page into `into`, each calling `on_chosen` with its position.
static func build_tabs(into: HBoxContainer, pages: Array[GasDebugPage], on_chosen: Callable) -> void:
	for existing: Node in into.get_children():
		existing.queue_free()
	for index: int in pages.size():
		var tab: Button = Button.new()
		tab.text = pages[index].title()
		tab.pressed.connect(on_chosen.bind(index))
		into.add_child(tab)


## An entity's own name, whichever of its two nodes has one, or its id.
static func named(snapshot: GasRuntimeSnapshot) -> String:
	if snapshot == null:
		return ""
	if not snapshot.owner_name.is_empty():
		return snapshot.owner_name
	if not snapshot.avatar_name.is_empty():
		return snapshot.avatar_name
	return str(snapshot.asc_id)
