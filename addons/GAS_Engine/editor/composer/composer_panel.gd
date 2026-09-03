## The small pieces every panel is built from.
##
## The palette, the inspector and the output are the same handful of shapes in a
## different order: a caption, a label, a value slot, a rule. Written out in each
## of them they would be three copies drifting apart, and the third one would get
## a slightly different grey nobody could account for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerPanel extends RefCounted


static func label(text: String, tint: Color, font_size: int) -> Label:
	var made: Label = Label.new()
	made.text = text
	made.add_theme_color_override(GASEditorTheme.FONT_COLOR, tint)
	made.add_theme_font_size_override(GASEditorTheme.FONT_SIZE, font_size)
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made


## The small dim word that names a region: PALETTE, INSPECTOR, OUTPUT.
##
## Quiet on purpose. A heading loud enough to compete with the content is a
## heading that gets read every time instead of once.
static func caption(text: String) -> Label:
	return label(text, ComposerTheme.TEXT_FAINT, ComposerTheme.FONT_LABEL)


## A value in a box: the shape a field takes in a card and in the inspector, so
## the same value looks like the same thing wherever it is read.
static func slot(text: String, tint: Color, width: float) -> PanelContainer:
	var box: PanelContainer = PanelContainer.new()
	box.custom_minimum_size = Vector2(width, 0.0)
	box.add_theme_stylebox_override(
		GASEditorTheme.PANEL_STYLEBOX, ComposerTheme.field_box()
	)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var value: Label = label(text, tint, ComposerTheme.FONT_VALUE)
	value.clip_text = true
	box.add_child(value)
	return box


## A hairline. Used to separate regions rather than to decorate them, so it is
## barely above the background: a border that announces itself turns a layout
## into a grid of boxes.
static func rule(at: Vector2, span: Vector2) -> ColorRect:
	var line: ColorRect = ColorRect.new()
	line.position = at
	line.size = span
	line.color = ComposerTheme.RULE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## A filled region behind a panel, so the chrome reads as the frame and the
## canvas as the thing inside it.
static func backdrop(tint: Color) -> ColorRect:
	var back: ColorRect = ColorRect.new()
	back.color = tint
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return back


## A column with the project's spacing already on it.
static func column(separation: float) -> VBoxContainer:
	var made: VBoxContainer = VBoxContainer.new()
	made.add_theme_constant_override(GASEditorTheme.SEPARATION, int(separation))
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made


static func row(separation: float) -> HBoxContainer:
	var made: HBoxContainer = HBoxContainer.new()
	made.add_theme_constant_override(GASEditorTheme.SEPARATION, int(separation))
	made.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return made
