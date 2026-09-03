## One node, drawn.
##
## Glass rather than a solid fill, so the card takes the colour of the glow it
## stands on. Every card shares that treatment, so it cannot also mean anything:
## a node that suspends the ability says `await` in its title instead. A label is
## read; a texture is only felt.
##
## Cut to its content in two steps. A card cannot be measured before it exists -
## a Control outside the tree has no theme resolved, so its children do not yet
## know how tall they are and the measurement comes back far too small. So the
## glass goes in at a placeholder size, the content on top, and `fit()` trims
## both once a frame has passed. A height written by hand instead is a height
## that stops matching the moment a field is added, and the field boxes spill out
## of the panel.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCard extends Control

const AWAIT_LABEL: String = "await"
const MISSING_LABEL: String = "not connected"
const CHEVRON: String = "⌄"

## How much of a card is worth drawing.
##
## Zoom alone is not enough, and it shows the moment anyone tries it: pulled
## back far enough to see the shape of a flow, the fields are smudges and the
## card is still spending its space drawing text nobody can read. Pulling back
## is for seeing the shape - how many branches, where they meet, what is red -
## and a block says that better than a full card does.
enum Detail { FULL, TITLE, BLOCK }

var node_id: StringName = &""

var _glass: ColorRect = null
var _column: VBoxContainer = null
var _ring: ReferenceRect = null
var _title: Control = null
var _rows: Array[Control] = []
var _state: ComposerNode.State = ComposerNode.State.CLEAN


## Build the card for `node`. Its size is provisional until `fit()` runs.
func build(node: ComposerNode) -> void:
	node_id = node.id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ComposerTheme.NODE_WIDTH, 0.0)

	_glass = ColorRect.new()
	_glass.size = Vector2(ComposerTheme.NODE_WIDTH, 1.0)
	_glass.material = ComposerShaders.glass_material(_glass.size)
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glass)

	_column = VBoxContainer.new()
	_column.position = Vector2(ComposerTheme.PAD_X, ComposerTheme.PAD_Y)
	_column.custom_minimum_size = Vector2(
		ComposerTheme.NODE_WIDTH - ComposerTheme.PAD_X * 2.0, 0.0
	)
	_column.add_theme_constant_override(GASEditorTheme.SEPARATION, int(ComposerTheme.S3 - 1.0))
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_state = node.state
	_title = _title_row(node)
	_column.add_child(_title)
	for field: ComposerNode.Field in node.fields:
		var row: Control = _field_row(field)
		_rows.append(row)
		_column.add_child(row)

	if node.awaits:
		add_child(_await_mark())

	# Drawn rather than styled: a ReferenceRect is a border and nothing else,
	# which is all a selection needs to be.
	_ring = ReferenceRect.new()
	_ring.editor_only = false
	_ring.border_color = ComposerTheme.ACCENT
	_ring.border_width = ComposerTheme.RING_WIDTH
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	add_child(_ring)


## Trim the card to what its content turned out to be.
##
## Call one frame after the card is in the tree, never before: the column has no
## measured height until then.
func fit() -> void:
	if _column == null or _glass == null:
		return
	var height: float = _column.size.y + ComposerTheme.PAD_Y * 2.0
	var span: Vector2 = Vector2(ComposerTheme.NODE_WIDTH, height)
	_glass.size = span
	ComposerShaders.resize_glass(_glass.material as ShaderMaterial, span)
	size = span
	if _ring != null:
		_ring.size = span


## Whether this card is one of the ones being worked on.
func pick(on: bool) -> void:
	if _ring != null:
		_ring.visible = on


## Draw as much of this card as is worth reading at the current zoom.
##
## The card keeps its size at every level. Shrinking it as its contents go away
## would move every port on it, and the wires with them - the graph would appear
## to rearrange itself while somebody was only pulling back to look at it.
func show_detail(level: ComposerCard.Detail) -> void:
	if _title != null:
		_title.visible = level != ComposerCard.Detail.BLOCK
	for row: Control in _rows:
		row.visible = level == ComposerCard.Detail.FULL
	if _glass != null:
		# With the dot hidden, the block itself has to carry the state, or
		# pulling back would hide exactly what pulling back is for.
		_glass.modulate = (
			ComposerTheme.severity_color(ComposerNode.severity_of(_state))
			if level == ComposerCard.Detail.BLOCK
			else Color.WHITE
		)


#region Rows
## The title, and the dot that carries this node's diagnostic state.
func _title_row(node: ComposerNode) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(GASEditorTheme.SEPARATION, int(ComposerTheme.S2 + 1.0))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var holder: CenterContainer = CenterContainer.new()
	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(7.0, 7.0)
	var tint: Color = ComposerTheme.severity_color(
		ComposerNode.severity_of(node.state)
	)
	dot.add_theme_stylebox_override(
		GASEditorTheme.PANEL_STYLEBOX, ComposerTheme.disc(tint, 3.5)
	)
	holder.add_child(dot)
	row.add_child(holder)

	row.add_child(
		_label(node.title, ComposerTheme.TEXT, ComposerTheme.FONT_TITLE)
	)
	return row


## A field: a small dim caption above, the value in a slot below.
##
## Never on one line. Stacking them is what keeps a dense card legible without
## making it wider.
func _field_row(field: ComposerNode.Field) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(GASEditorTheme.SEPARATION, int(ComposerTheme.S1))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(
		_label(field.label, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_LABEL)
	)

	var slot: PanelContainer = PanelContainer.new()
	slot.add_theme_stylebox_override(GASEditorTheme.PANEL_STYLEBOX, ComposerTheme.field_box())
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(slot)

	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(line)

	# A required value that is absent is an error, and is drawn as one. The words
	# differ from the Output panel's on purpose - the row names the node, and on
	# a card the title has already said it - but the severity may not, and it did
	# for a while: amber here and red there, over one missing argument.
	var absent: bool = not field.is_satisfied()
	var value: Label = _label(
		MISSING_LABEL if absent else field.display,
		(
			ComposerTheme.severity_color(ComposerGraph.Severity.ERROR) if absent
			else ComposerTheme.TEXT
		),
		ComposerTheme.FONT_VALUE
	)
	value.clip_text = true
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(value)

	if field.source == ComposerNode.ValueSource.WIRED:
		line.add_child(
			_label(CHEVRON, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_VALUE)
		)
	return column


func _await_mark() -> Control:
	var mark: Label = _label(
		AWAIT_LABEL, ComposerTheme.ACCENT_SOFT, ComposerTheme.FONT_LABEL
	)
	mark.position = Vector2(
		ComposerTheme.NODE_WIDTH - 58.0, ComposerTheme.PAD_Y + 1.0
	)
	return mark


func _label(text: String, tint: Color, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override(GASEditorTheme.FONT_COLOR, tint)
	label.add_theme_font_size_override(GASEditorTheme.FONT_SIZE, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
#endregion
