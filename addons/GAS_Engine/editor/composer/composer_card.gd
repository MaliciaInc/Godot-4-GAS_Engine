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
## @meta_license: MIT
class_name ComposerCard extends Control

const AWAIT_LABEL: String = "await"
const MISSING_LABEL: String = "not connected"
const CHEVRON: String = "⌄"

var node_id: StringName = &""

var _glass: ColorRect = null
var _column: VBoxContainer = null


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
	_column.add_theme_constant_override(DashboardTheme.SEPARATION, int(ComposerTheme.S3 - 1.0))
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)

	_column.add_child(_title_row(node))
	for field: ComposerNode.Field in node.fields:
		_column.add_child(_field_row(field))

	if node.awaits:
		add_child(_await_mark())


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


#region Rows
## The title, and the dot that carries this node's diagnostic state.
func _title_row(node: ComposerNode) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(DashboardTheme.SEPARATION, int(ComposerTheme.S2 + 1.0))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var holder: CenterContainer = CenterContainer.new()
	var dot: Panel = Panel.new()
	dot.custom_minimum_size = Vector2(7.0, 7.0)
	var tint: Color = ComposerTheme.severity_color(
		ComposerNode.severity_of(node.state)
	)
	dot.add_theme_stylebox_override(
		DashboardTheme.PANEL_STYLEBOX, ComposerTheme.disc(tint, 3.5)
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
	column.add_theme_constant_override(DashboardTheme.SEPARATION, int(ComposerTheme.S1))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(
		_label(field.label, ComposerTheme.TEXT_DIM, ComposerTheme.FONT_LABEL)
	)

	var slot: PanelContainer = PanelContainer.new()
	slot.add_theme_stylebox_override(DashboardTheme.PANEL_STYLEBOX, ComposerTheme.field_box())
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(slot)

	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(line)

	# A required value that is absent says so, in the same words and the same
	# colour the Output panel uses. Both read `field.source`, so neither is
	# deciding it on its own and they cannot contradict each other.
	var absent: bool = not field.is_satisfied()
	var value: Label = _label(
		MISSING_LABEL if absent else field.display,
		ComposerTheme.WARNING if absent else ComposerTheme.TEXT,
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
	label.add_theme_color_override(DashboardTheme.FONT_COLOR, tint)
	label.add_theme_font_size_override(DashboardTheme.FONT_SIZE, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
#endregion
