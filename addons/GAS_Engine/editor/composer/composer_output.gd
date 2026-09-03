## Everything the tooling has to say, in one place.
##
## One tab, not two. Splitting diagnostics from output was splitting one list in
## half and making a person guess which half something landed in.
##
## Each row carries the file and line it applies to, because a message without a
## place is a message that sends someone hunting.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerOutput extends Control

const TITLE: String = "Output"
const NOTHING: String = "Nothing to report"
const NODE_WORD: String = "node"
const NOTE_WORD: String = "note"
const READ_ONLY: String = "Read-only — "
const NOT_DRAWN: String = "Nothing to draw"
const PICK_ONE: String = "Open an ability…"
const HOW_TO_OPEN: String = (
	"Open an ability in the Script editor, then choose Ability Composer again. "
	+ "There are six to start from in addons/GAS_Engine/reference/."
)
const ROW_PITCH: float = 28.0
const COUNT_INSET: float = 190.0

signal row_picked(node_id: StringName, line: int)

## Somebody took the panel up on its suggestion. Who owns a file dialog is
## not this panel's business - it says what is wanted and the plugin acts.
signal open_requested

var _rows: VBoxContainer = null
var _edge: ColorRect = null
var _count: Label = null


func _ready() -> void:
	var back: ColorRect = ComposerPanel.backdrop(ComposerTheme.CHROME)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_edge = ComposerPanel.rule(Vector2.ZERO, Vector2(size.x, 1.0))
	add_child(_edge)

	var head: Label = ComposerPanel.label(
		TITLE, ComposerTheme.TEXT, ComposerTheme.FONT_VALUE
	)
	head.position = Vector2(ComposerTheme.S4, ComposerTheme.S3 + 2.0)
	add_child(head)

	var underline: ColorRect = ColorRect.new()
	underline.position = Vector2(ComposerTheme.S4 - 2.0, ComposerTheme.S4 + 13.0)
	underline.size = Vector2(48.0, 2.0)
	underline.color = ComposerTheme.ACCENT
	add_child(underline)

	_count = ComposerPanel.label(
		"", ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_LABEL + 1
	)
	add_child(_count)

	# Anything placed from `size` in `_ready()` is placed from a size the parent
	# has not set yet - this panel is added first and laid out afterwards, so at
	# this point it is still zero wide. Following `resized` is what puts the
	# count in its own panel instead of off the left edge of the screen.
	resized.connect(_arrange)
	_arrange()

	_rows = ComposerPanel.column(ComposerTheme.S2)
	_rows.position = Vector2(ComposerTheme.S4, ComposerTheme.S4 + 30.0)
	add_child(_rows)


func _arrange() -> void:
	if _count == null or _edge == null:
		return
	_count.position = Vector2(size.x - COUNT_INSET, ComposerTheme.S3 + 2.0)
	_edge.size = Vector2(size.x, 1.0)


## Report on `graph`: why it cannot be edited, or what is wrong inside it.
func show_graph(graph: ComposerGraph) -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	if graph == null:
		_count.text = ""
		return

	_count.text = "%s · %s" % [
		_plural(graph.nodes.size(), NODE_WORD), _plural(graph.diagnostics.size(), NOTE_WORD)
	]
	if graph.diagnostics.is_empty():
		_rows.add_child(
			ComposerPanel.label(
				NOTHING, ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_VALUE
			)
		)
		return

	for found: ComposerGraph.Diagnostic in graph.diagnostics:
		_rows.add_child(_row(found, graph.source_path))


## Say why there is nothing on the canvas, and what to do about it.
##
## Distinct from `show_graph(null)`, which is the panel holding nothing because
## nothing has happened yet. This is the panel holding nothing *for a reason*,
## and the reason is the whole value: a person who just chose a menu item and
## got an unchanged screen has been told the tool is broken.
func show_refusal(reason: String) -> void:
	show_graph(null)
	_count.text = NOT_DRAWN
	_rows.add_child(
		ComposerPanel.label(reason, ComposerTheme.TEXT, ComposerTheme.FONT_VALUE)
	)
	_rows.add_child(
		ComposerPanel.label(HOW_TO_OPEN, ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_VALUE)
	)

	# Telling a person to go and open a file, from a screen they reached through
	# a menu, is telling them the tool cannot do the thing they just asked for.
	var pick: Button = Button.new()
	pick.text = PICK_ONE
	pick.flat = true
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.add_theme_color_override(DashboardTheme.FONT_COLOR, ComposerTheme.ACCENT)
	pick.add_theme_font_size_override(DashboardTheme.FONT_SIZE, ComposerTheme.FONT_VALUE)
	pick.pressed.connect(func _asked() -> void: open_requested.emit())
	_rows.add_child(pick)


func _row(found: ComposerGraph.Diagnostic, source_path: String) -> Control:
	var line: HBoxContainer = ComposerPanel.row(ComposerTheme.S2)
	var tint: Color = ComposerTheme.severity_color(found.severity)

	line.add_child(
		ComposerPanel.label(
			ComposerTheme.severity_mark(found.severity), tint, ComposerTheme.FONT_VALUE
		)
	)

	# A file this tool cannot draw is not an error in the file. Saying so in the
	# message keeps a person from hunting for a mistake they did not make.
	var prefix: String = (
		READ_ONLY if found.severity == ComposerGraph.Severity.NOT_REPRESENTABLE else ""
	)
	var text: Label = ComposerPanel.label(
		prefix + found.message, tint, ComposerTheme.FONT_VALUE
	)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)

	line.add_child(
		ComposerPanel.label(
			_place(source_path, found.span), ComposerTheme.TEXT_FAINT,
			ComposerTheme.FONT_LABEL + 1
		)
	)

	# A row already prints `file.gd:61`, which is the shape every editor lets a
	# person click. Printing it and doing nothing when they do is the panel
	# telling them where to look and then leaving them to find it.
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	line.gui_input.connect(_on_row_input.bind(found))
	return line


func _on_row_input(event: InputEvent, found: ComposerGraph.Diagnostic) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	row_picked.emit(found.node_id, found.span.first_line)


## `1 node`, `4 nodes`. A tool that writes "1 notes" reads as one nobody
## finished, and a reader who notices that wonders what else was left.
static func _plural(count: int, word: String) -> String:
	return "%d %s%s" % [count, word, "" if count == 1 else "s"]


## `file.gd:61`, the shape every editor lets you click.
static func _place(source_path: String, span: ComposerSpan) -> String:
	if not span.is_valid():
		return ""
	return "%s:%d" % [source_path.get_file(), span.first_line]
