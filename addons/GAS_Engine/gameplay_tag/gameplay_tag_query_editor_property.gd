## Building a nested tag query by clicking rather than by hand-wiring
## Resources.
##
## `((A and B) or C) and not D` is four expressions and a shape, and authoring
## it in the default inspector means creating a GameplayTagQueryExpression,
## opening it, creating two more inside it, and typing the tags - with nothing
## on screen saying what the whole thing asks. This draws the tree: one row per
## expression with its operator, one row per tag, and the picker on the leaves
## so a tag is chosen from what the project declares instead of typed.
##
## Nothing decides anything here. Every edit is one call into
## GameplayTagQueryEdits and every row comes from `rows_of`, because Godot
## refuses to build an EditorProperty outside the editor - a rule written in
## this file would be a rule nothing can check.
##
## No `class_name`, so a running game has no path by which it loads this. It is
## preloaded by the inspector plugin, which is the only thing that wants it.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends EditorProperty

const POPUP_TITLE: String = "Gameplay Tag Query"
const POPUP_SIZE: Vector2i = Vector2i(760, 620)
const PICKER_TITLE: String = "Choose a Tag"
const PICKER_SIZE: Vector2i = Vector2i(600, 700)
const POPUP_MARGIN: int = 8

## What the property row says: how many conditions the query holds, or that it
## holds none - which is not the same as holding a query that matches nothing.
const EMPTY_LABEL: String = "No query (matches everything)"
const SUMMARY: String = "%s — %d condition(s)"

## The three per-row actions, as the plain ids a Tree's buttons carry.
##
## Ints rather than an enum because the file declares no `class_name`: a bare
## `Action` annotation would bind to whatever global class is called Action in
## the project this addon is installed into, and qualifying it would mean this
## file preloading itself by path. Godot's own button API takes an int.
const ADD_TAG: int = 0
const ADD_NESTED: int = 1
const REMOVE: int = 2

const ACTION_TOOLTIPS: Array[String] = [
	"Add a tag to this expression",
	"Add a nested expression",
	"Remove this",
]

## How far one level of nesting is drawn in.
const INDENT: String = "    "

var _button: Button = Button.new()
var _popup: Window = null
var _tree: Tree = null
var _picker: Window = null

## The expression a tag is being picked for, while the picker is open.
var _picking_for: GameplayTagQueryExpression = null


#region Lifecycle
func _init() -> void:
	_button.clip_text = true
	_button.pressed.connect(_on_button_pressed)
	add_child(_button)
	add_focusable(_button)


func _update_property() -> void:
	_sync_button()
	if is_instance_valid(_popup) and _popup.visible:
		_refresh_tree()


## The query the inspected object holds, or null when it holds none.
func _edited_query() -> GameplayTagQuery:
	var object: Object = get_edited_object()
	if not is_instance_valid(object):
		return null
	var held: Variant = object.get(get_edited_property())
	if held is GameplayTagQuery:
		var query: GameplayTagQuery = held
		return query
	return null


func _sync_button() -> void:
	var query: GameplayTagQuery = _edited_query()
	if query == null or query.root == null:
		_button.text = EMPTY_LABEL
		return
	_button.text = SUMMARY % [
		GameplayTagQueryEdits.named(query.root.operator),
		GameplayTagQueryEdits.rows_of(query).size() - 1,
	]
#endregion


#region The popup
func _on_button_pressed() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()

	_popup = GASEditorPopup.opened(POPUP_TITLE, POPUP_SIZE, _on_popup_close_requested)
	_build_body(_popup)
	_refresh_tree()


func _on_popup_close_requested() -> void:
	if is_instance_valid(_picker):
		_picker.queue_free.call_deferred()
	if is_instance_valid(_popup):
		_popup.queue_free.call_deferred()


func _build_body(parent: Window) -> void:
	var body: VBoxContainer = GASEditorPopup.body_of(parent, POPUP_MARGIN)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.item_edited.connect(_on_row_edited)
	_tree.button_clicked.connect(_on_row_button)
	body.add_child(_tree)
#endregion


#region Drawing what the query says
## Redraw every row from the query itself.
##
## Rebuilt whole rather than patched, so what is on screen is what the runtime
## would evaluate. A tree the editor kept in step by hand is a second model of
## the query, and two models of one thing disagree.
func _refresh_tree() -> void:
	if not is_instance_valid(_tree):
		return
	_tree.clear()
	var query: GameplayTagQuery = _edited_query()
	if query == null:
		return
	GameplayTagQueryEdits.ensure_root(query)

	var root: TreeItem = _tree.create_item()
	var rows: Array[GameplayTagQueryEdits.Row] = GameplayTagQueryEdits.rows_of(query)
	for index: int in rows.size():
		_draw_row(root, rows[index], index == 0)


func _draw_row(
	under: TreeItem, row: GameplayTagQueryEdits.Row, is_the_root: bool
) -> void:
	var item: TreeItem = _tree.create_item(under)
	item.set_metadata(0, row)

	if row.is_a_tag():
		item.set_text(0, INDENT.repeat(row.depth) + row.shown())
		_add_button(item, REMOVE)
		return

	# The operator is a range cell rather than a label plus a dropdown: it is
	# one of three values, and a Tree already knows how to edit one of those.
	item.set_cell_mode(0, TreeItem.CELL_MODE_RANGE)
	item.set_text(0, GameplayTagQueryEdits.OPERATOR_CHOICES)
	item.set_range(0, int(row.expression.operator))
	item.set_editable(0, true)

	_add_button(item, ADD_TAG)
	_add_button(item, ADD_NESTED)
	# The root has nowhere to be removed from: a query without one is a query
	# that matches everything, which is what clearing the property says.
	if not is_the_root:
		_add_button(item, REMOVE)


func _add_button(item: TreeItem, action: int) -> void:
	item.add_button(0, _icon_for(action), action, false, ACTION_TOOLTIPS[action])


## The host editor's own icons, so the buttons read the way every other tree in
## the inspector does.
func _icon_for(action: int) -> Texture2D:
	var theme: Theme = EditorInterface.get_editor_theme()
	match action:
		ADD_TAG:
			return theme.get_icon(GASEditorTheme.ICON_ADD, GASEditorTheme.EDITOR_ICON_THEME)
		ADD_NESTED:
			return theme.get_icon(
				GASEditorTheme.ICON_FOLDER, GASEditorTheme.EDITOR_ICON_THEME
			)
		_:
			return theme.get_icon(GASEditorTheme.ICON_REMOVE, GASEditorTheme.EDITOR_ICON_THEME)
#endregion


#region Editing
func _row_of(item: TreeItem) -> GameplayTagQueryEdits.Row:
	if item == null:
		return null
	var held: Variant = item.get_metadata(0)
	if held is GameplayTagQueryEdits.Row:
		var row: GameplayTagQueryEdits.Row = held
		return row
	return null


## Changing an operator changes what the expression means and nothing else.
func _on_row_edited() -> void:
	var row: GameplayTagQueryEdits.Row = _row_of(_tree.get_edited())
	if row == null or row.is_a_tag():
		return
	var chosen: int = int(_tree.get_edited().get_range(0))
	GameplayTagQueryEdits.set_operator(row.expression, chosen as GameplayTagQueryExpression.Operator)
	_published()


func _on_row_button(
	item: TreeItem, _column: int, id: int, _mouse_button_index: int
) -> void:
	var row: GameplayTagQueryEdits.Row = _row_of(item)
	if row == null:
		return
	match id:
		ADD_TAG:
			_open_picker(row.expression)
		ADD_NESTED:
			GameplayTagQueryEdits.nest(row.expression)
			_published()
		REMOVE:
			_remove(row)


## Removing a tag row removes the tag; removing an expression row removes it
## from whichever expression holds it.
##
## Found by walking the query rather than by remembering a parent on the row,
## because the tree is rebuilt on every edit and a parent remembered before the
## last one is a parent that may no longer hold this.
func _remove(row: GameplayTagQueryEdits.Row) -> void:
	if row.is_a_tag():
		GameplayTagQueryEdits.remove_tag(row.expression, row.tag)
		_published()
		return

	var query: GameplayTagQuery = _edited_query()
	if query == null:
		return
	for other: GameplayTagQueryEdits.Row in GameplayTagQueryEdits.rows_of(query):
		if other.is_a_tag():
			continue
		if GameplayTagQueryEdits.drop(other.expression, row.expression):
			break
	_published()


## Say the property changed, and redraw.
##
## The query is a Resource the object already holds, so an edit has already
## landed in it; `emit_changed` is what makes the scene dirty and puts the edit
## on the undo stack, which is what somebody expects of an inspector.
func _published() -> void:
	emit_changed(get_edited_property(), _edited_query())
	_sync_button()
	_refresh_tree()
#endregion


#region The leaf picker
func _open_picker(for_expression: GameplayTagQueryExpression) -> void:
	_picking_for = for_expression
	if is_instance_valid(_picker):
		_picker.queue_free()

	_picker = GASEditorPopup.opened(PICKER_TITLE, PICKER_SIZE, _on_picker_close_requested)
	var body: VBoxContainer = GASEditorPopup.body_of(_picker, POPUP_MARGIN)

	var search: LineEdit = LineEdit.new()
	search.placeholder_text = GameplayTagTree.SEARCH_PLACEHOLDER
	search.clear_button_enabled = true
	body.add_child(search)

	var tags: Tree = Tree.new()
	tags.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tags.hide_root = true
	body.add_child(tags)

	search.text_changed.connect(
		func(_text: String) -> void: _fill_picker(tags, search.text)
	)
	tags.item_activated.connect(func() -> void: _on_tag_chosen(tags))
	_fill_picker(tags, "")


func _fill_picker(tags: Tree, filter: String) -> void:
	# The one tag tree in the addon, so a tag is grouped here exactly as it is
	# everywhere else. Nothing is unavailable: a tag already in this expression
	# is simply not added twice.
	GameplayTagTree.build(
		tags, filter, [] as Array[StringName], GameplayTagTree.Style.new()
	)


func _on_tag_chosen(tags: Tree) -> void:
	var item: TreeItem = tags.get_selected()
	if item == null or _picking_for == null:
		return
	# Only leaves carry a tag; a grouping row is a segment, not something the
	# registry declares.
	var held: Variant = item.get_metadata(0)
	if not held is StringName:
		return
	var tag: StringName = held

	GameplayTagQueryEdits.add_tag(_picking_for, tag)
	_on_picker_close_requested()
	_published()


func _on_picker_close_requested() -> void:
	_picking_for = null
	if is_instance_valid(_picker):
		_picker.queue_free.call_deferred()
#endregion
