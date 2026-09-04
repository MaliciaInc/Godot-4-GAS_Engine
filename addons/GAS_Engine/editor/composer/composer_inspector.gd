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
## The control is the same one the card puts in its own rows. Two panels drawing
## one argument two ways is two pictures of one fact, and they disagree the
## moment either is wrong - a bool the card ticks and the panel spells, a name
## the card writes `&"fire"` and the panel writes `fire`. There is one control,
## it belongs to neither of them, and both ask it.
##
## A value fed by a cable is not typed here either. The cable is the edit, and
## this panel offers to take it off rather than a second way to set the same
## argument behind it.
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

## What the button that takes a cable off says.
const UNPLUGGED: String = "Disconnect"

## Somebody asked for the cable on this argument to come off. Carries where, not
## what: the panel never decides what unplugging writes.
signal disconnect_requested(node_id: StringName, position: int)

var _collapsed: bool = false
var _shown: ComposerNode = null
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
	_grip.add_theme_color_override(GASEditorTheme.FONT_COLOR, ComposerTheme.TEXT_DIM)
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
func show_node(node: ComposerNode, may_write: bool = false) -> void:
	_shown = node
	_may_write = may_write
	# Detached before it is freed: `queue_free` waits for the end of the frame,
	# so a panel only queued is still a child, still laid out and still reachable
	# by index in the same frame this rebuilt it.
	for child: Node in _body.get_children():
		_body.remove_child(child)
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
		return block

	_edit(block, node, position)
	if field.source == ComposerNode.ValueSource.WIRED:
		block.add_child(_unplug(node, position))
	return block


## Put the one control a value is edited with into `block`.
##
## Added to the tree and then configured, in that order and to match the card:
## the control it builds resolves its theme from its parent, and one built
## outside the tree measures itself against nothing.
func _edit(block: Control, node: ComposerNode, position: int) -> void:
	var editor: ComposerValueEditor = ComposerValueEditor.new()
	editor.custom_minimum_size = Vector2(_width - ComposerTheme.S4 * 2.0, 0.0)
	editor.committed.connect(
		func _typed(source_text: String) -> void: _commit(node.id, position, source_text)
	)
	block.add_child(editor)
	editor.configure(node.fields[position], node.may_edit(node.fields[position]))


## Take the cable off this argument.
##
## An intention, not an edit: the panel says what somebody asked for and the
## screen decides whether the file can say it. Writing the declared default here
## would be this panel holding a second opinion about what unplugging means,
## beside the one the connection controller already has.
func _unplug(node: ComposerNode, position: int) -> Control:
	var button: Button = Button.new()
	button.text = UNPLUGGED
	button.add_theme_font_size_override(
		GASEditorTheme.FONT_SIZE, ComposerTheme.FONT_LABEL
	)
	button.pressed.connect(
		func _asked() -> void: disconnect_requested.emit(node.id, position)
	)
	return button


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
