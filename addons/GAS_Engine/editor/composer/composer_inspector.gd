## The selected node, edited by hand.
##
## Collapsible, because a wide graph wants the width back and this panel is only
## worth its column while something is selected. The grip sits on its own edge so
## the control is where the thing it controls is.
##
## Shows the same fields the card shows, in the same words: a value that is
## absent reads `not connected` here too, because both ask the field rather than
## deciding for themselves.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name ComposerInspector extends Control

const TITLE: String = "INSPECTOR"
const NOTHING_SELECTED: String = "Nothing selected"
const OPEN_MARK: String = "›"
const SHUT_MARK: String = "‹"
const ROW_PITCH: float = 70.0

signal collapsed_changed(collapsed: bool)

var _collapsed: bool = false
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
func show_node(node: ComposerNode) -> void:
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
	for field: ComposerNode.Field in node.fields:
		_body.add_child(_field_block(field))


func _field_block(field: ComposerNode.Field) -> Control:
	var block: VBoxContainer = ComposerPanel.column(ComposerTheme.S1)
	block.add_child(
		ComposerPanel.label(
			field.label, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_LABEL
		)
	)

	var absent: bool = not field.is_satisfied()
	block.add_child(
		ComposerPanel.slot(
			ComposerCard.MISSING_LABEL if absent else field.display,
			ComposerTheme.WARNING if absent else ComposerTheme.TEXT,
			_width - ComposerTheme.S4 * 2.0
		)
	)
	return block


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
