## The selected node, and where its values are typed.
##
## Collapsible, because a wide graph wants the width back and this panel is only
## worth its column while something is selected. The grip sits on its own edge so
## the control is where the thing it controls is.
##
## Shows the same fields the card shows, in the same words and the same colours:
## a value that is absent reads `not connected` here too, and in the same red,
## because both ask the field rather than deciding for themselves.
##
## Not every value is offered the same way. One that arrives on a cable is
## offered as a choice of what feeds it - the locals above it that fit - because
## that is what a cable is: a name in an argument. Choosing a different one
## rewires; typing a value instead disconnects. The node answers which control
## belongs to which value; this only draws the answer.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerInspector extends Control

const TITLE: String = "INSPECTOR"
const NOTHING_SELECTED: String = "Nothing selected"
const OPEN_MARK: String = "›"
const SHUT_MARK: String = "‹"

signal collapsed_changed(collapsed: bool)

## A value somebody typed. Carries where it goes rather than what it is, so the
## panel never has to hold a reference to the graph it is drawing.
signal value_edited(node_id: StringName, position: int, written: String)

const WIRED_MARK: String = "⌄ "

## The entry that is not a local: taking the cable off.
const UNPLUGGED: String = "— not from a cable —"

var _collapsed: bool = false
var _shown: ComposerNode = null
var _graph: ComposerGraph = null
var _may_write: bool = false
var _body: VBoxContainer = null
var _grip: Button = null
var _width: float = 0.0


func _ready() -> void:
	_width = size.x
	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	_grip = Button.new()
	_grip.text = OPEN_MARK
	_grip.flat = true
	_grip.position = Vector2(-ComposerTheme.S3 - 1.0, ComposerTheme.S4)
	_grip.custom_minimum_size = Vector2(ComposerTheme.S4, ComposerTheme.S4)
	_grip.add_theme_color_override(DashboardTheme.FONT_COLOR, ComposerTheme.TEXT_DIM)
	_grip.pressed.connect(toggle)
	add_child(_grip)

	_body = ComposerPanel.column(ComposerTheme.S2)
	_body.position = Vector2(ComposerTheme.S4, ComposerTheme.S4)
	add_child(_body)
	show_node(null)


## Draw `node`, or say plainly that nothing is selected.
##
## An empty panel and a panel showing nothing look the same, and one of them is
## a bug. Saying it removes the question.
func show_node(
	node: ComposerNode, may_write: bool = false, graph: ComposerGraph = null
) -> void:
	_graph = graph
	_shown = node
	_may_write = may_write
	for child: Node in _body.get_children():
		child.queue_free()

	_body.add_child(ComposerPanel.caption(TITLE))
	if node == null:
		_body.add_child(
			ComposerPanel.label(
				NOTHING_SELECTED, ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_VALUE
			)
		)
		return

	_body.add_child(
		ComposerPanel.label(node.title, ComposerTheme.TEXT, ComposerTheme.FONT_TITLE)
	)
	for position: int in node.fields.size():
		_body.add_child(_field_block(node, position))


func _field_block(node: ComposerNode, position: int) -> Control:
	var field: ComposerNode.Field = node.fields[position]
	var block: VBoxContainer = ComposerPanel.column(ComposerTheme.S1)
	block.add_child(
		ComposerPanel.label(
			field.label, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_LABEL
		)
	)
	if not _may_write or not node.may_edit(field):
		block.add_child(_read_only(field))
	elif node.may_type(field):
		block.add_child(_box(node, position))
	else:
		block.add_child(_feeds(node, position))
	return block


## What a cable could be attached to instead.
##
## The locals above this statement that fit the argument, and one entry that is
## not a local at all: choosing it writes an empty value, which is how a cable
## is taken off. Free text is not offered here because a cable is a name, and a
## box inviting anything would invite the thing that is not one.
func _feeds(node: ComposerNode, position: int) -> Control:
	var field: ComposerNode.Field = node.fields[position]
	var choice: OptionButton = OptionButton.new()
	choice.custom_minimum_size = Vector2(_width - ComposerTheme.S4 * 2.0, 0.0)
	choice.add_theme_color_override(DashboardTheme.FONT_COLOR, ComposerTheme.TEXT)
	choice.add_theme_font_size_override(DashboardTheme.FONT_SIZE, ComposerTheme.FONT_VALUE)

	var offered: Array[String] = [field.display]
	for port: ComposerNode.Port in _reachable(node, field):
		if port.label != field.display:
			offered.append(port.label)
	offered.append(UNPLUGGED)

	for name: String in offered:
		choice.add_item(name)
	choice.selected = 0
	choice.item_selected.connect(
		func _took(index: int) -> void:
			_commit(node.id, position, "" if offered[index] == UNPLUGGED else offered[index])
	)
	return choice


func _reachable(node: ComposerNode, field: ComposerNode.Field) -> Array[ComposerNode.Port]:
	return _graph.locals_reaching(node, field.type_name) if _graph != null else []


## A value that cannot be typed, shown as what it is.
##
## An absent one is drawn in the colour the Output panel gives it, which is the
## colour of an error - the file will not compile without it. Amber here and red
## there, over one fact, is how a person concludes their ability still runs.
func _read_only(field: ComposerNode.Field) -> Control:
	var absent: bool = not field.is_satisfied()
	var wired: bool = field.source == ComposerNode.ValueSource.WIRED
	var text: String = field.display
	if absent:
		text = ComposerCard.MISSING_LABEL
	elif wired:
		text = WIRED_MARK + field.display

	var tint: Color = ComposerTheme.TEXT
	if absent:
		tint = ComposerTheme.severity_color(ComposerGraph.Severity.ERROR)
	elif wired:
		tint = ComposerTheme.TEXT_DIM
	return ComposerPanel.slot(text, tint, _width - ComposerTheme.S4 * 2.0)


## A value somebody can type over.
##
## Committed when the box is left or the line is submitted, not on every
## keystroke: a graph that redrew itself per character would fight the person
## typing, and a save is the only thing that reaches the file anyway.
func _box(node: ComposerNode, position: int) -> Control:
	var written: LineEdit = LineEdit.new()
	written.text = node.fields[position].display
	written.custom_minimum_size = Vector2(_width - ComposerTheme.S4 * 2.0, 0.0)
	written.add_theme_stylebox_override(
		DashboardTheme.NORMAL_STYLEBOX, ComposerTheme.field_box()
	)
	written.add_theme_color_override(DashboardTheme.FONT_COLOR, ComposerTheme.TEXT)
	written.add_theme_font_size_override(
		DashboardTheme.FONT_SIZE, ComposerTheme.FONT_VALUE
	)
	written.text_submitted.connect(
		func _submitted(text: String) -> void: _commit(node.id, position, text)
	)
	written.focus_exited.connect(
		func _left() -> void: _commit(node.id, position, written.text)
	)
	return written


func _commit(node_id: StringName, position: int, written: String) -> void:
	if not _may_write or _shown == null or _shown.id != node_id:
		return
	if _shown.fields[position].display == written:
		return
	value_edited.emit(node_id, position, written)


#region Collapsing
func toggle() -> void:
	set_collapsed(not _collapsed)


func set_collapsed(shut: bool) -> void:
	if shut == _collapsed:
		return
	_collapsed = shut
	_body.visible = not shut
	_grip.text = SHUT_MARK if shut else OPEN_MARK
	collapsed_changed.emit(shut)


func is_collapsed() -> bool:
	return _collapsed


## What the panel occupies right now: its full width, or just the grip.
##
## Asked rather than assumed by the screen that lays it out, so a collapsed
## inspector actually hands the canvas the space back instead of hiding its
## contents behind a column that still reserves them.
func occupied_width() -> float:
	return ComposerTheme.S4 if _collapsed else _width
#endregion
