## The dashboard's colours and styleboxes, derived from the editor's own theme.
##
## All three dashboard tabs did this themselves, which meant three copies of the
## same colour derivation and three chances for one of them to drift from the
## editor after a theme change.
##
## Styleboxes are created once and mutated in place, so a re-sync updates every
## control already holding one rather than leaving the old object behind.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT

@tool
class_name DashboardTheme extends RefCounted


## Meta key marking which palette slot a PanelContainer belongs to.
#: Godot's own theme vocabulary. Named here so the tabs ask the theme layer
#: rather than each retyping the engine's strings.
const EDITOR_THEME_TYPE: String = "Editor"
const EDITOR_ICON_THEME: String = "EditorIcons"
const ACCENT_COLOR: String = "accent_color"
const FONT_COLOR: String = "font_color"
const DISABLED_FONT_COLOR: String = "disabled_font_color"
const SUCCESS_COLOR: String = "success_color"
const ERROR_COLOR: String = "error_color"
const PANEL_STYLEBOX: String = "panel"
## The RichTextLabel slot whose stylebox paints its background.
const RICH_TEXT_STYLEBOX: String = "normal"

## Icon names Godot ships that the dashboards reuse.
const ICON_EDIT: String = "Edit"
const ICON_REMOVE: String = "Remove"
const ICON_COPY: String = "ActionCopy"
const ICON_EXPAND_TREE: String = "ExpandTree"
const ICON_COLLAPSE_TREE: String = "CollapseTree"

## Labels the tree toolbars share.
const LABEL_EXPAND_TREE: String = "Expand Tree"
const LABEL_COLLAPSE_TREE: String = "Collapse Tree"

const PANEL_TYPE_META: String = "panel_type"
const PANEL_BASE: String = "base"
const PANEL_DARK: String = "dark"
const PANEL_HEADER: String = "header"

## Stylebox resource names the original .tres files are recognised by.
const DARK_STYLE_MARKER: String = "editor_panel_flat_style_dark"
const BASE_STYLE_MARKER: String = "editor_panel_flat_style"

const PANEL_MARGIN: int = 5
const PANEL_RADIUS: int = 5
const HEADER_RADIUS: int = 8
const SELECTION_MARGIN: int = 15
const SELECTION_ALPHA: float = 0.25
const GUIDE_ALPHA: float = 0.15
const LIGHTEN_STEP: float = 0.08
const LIST_ITEM_STEP: float = 0.05
const LIST_ITEM_MARGIN: int = 8
const LIST_ITEM_RADIUS: int = 8

var base_panel: StyleBoxFlat = null
var dark_panel: StyleBoxFlat = null
var header_panel: StyleBoxFlat = null
var selection: StyleBoxFlat = null
## Rows in the cue list, one step off the dark panel behind them.
var list_item: StyleBoxFlat = null

var accent_html: String = ""
var text_accent: Color = Color.WHITE


#region Synchronisation
## Read the editor theme and refresh every derived style.
##
## Returns false outside the editor, or when the theme reads as fully black -
## which happens transiently during a hot reload and would otherwise repaint the
## whole dashboard in an unreadable palette.
func sync_from_editor() -> bool:
	if not Engine.is_editor_hint():
		return false
	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme == null:
		return false

	var base_color: Color = editor_theme.get_color("base_color", EDITOR_THEME_TYPE)
	var dark_color: Color = editor_theme.get_color("dark_color_1", EDITOR_THEME_TYPE)
	if base_color == Color.BLACK and dark_color == Color.BLACK:
		return false

	var accent: Color = editor_theme.get_color(ACCENT_COLOR, EDITOR_THEME_TYPE)
	accent_html = accent.to_html(false)
	text_accent = accent

	var is_dark: bool = base_color.get_luminance() < 0.5
	var header_color: Color = (
		base_color.lightened(LIGHTEN_STEP) if is_dark else base_color.darkened(LIGHTEN_STEP)
	)

	base_panel = _ensure(base_panel, PANEL_RADIUS, PANEL_MARGIN)
	dark_panel = _ensure(dark_panel, PANEL_RADIUS, PANEL_MARGIN)
	header_panel = _ensure(header_panel, HEADER_RADIUS, PANEL_MARGIN)
	selection = _ensure(selection, PANEL_RADIUS, SELECTION_MARGIN)
	list_item = _ensure(list_item, LIST_ITEM_RADIUS, LIST_ITEM_MARGIN)

	base_panel.bg_color = base_color
	dark_panel.bg_color = dark_color
	header_panel.bg_color = header_color
	selection.bg_color = accent * Color(1.0, 1.0, 1.0, SELECTION_ALPHA)
	list_item.bg_color = (
		dark_color.lightened(LIST_ITEM_STEP) if is_dark else dark_color.darkened(LIST_ITEM_STEP)
	)
	return true


## Reuse an existing box so controls already holding it see the new colours.
func _ensure(existing: StyleBoxFlat, radius: int, margin: int) -> StyleBoxFlat:
	if existing != null:
		return existing
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(radius)
	return box
#endregion


#region Application
## Repaint every PanelContainer under `root` that belongs to the palette.
##
## The slot is remembered as metadata the first time it is worked out from the
## original stylebox resource, because the override replaces that resource and
## the clue would otherwise be gone on the next pass.
func apply_panels(root: Node) -> void:
	var panel: PanelContainer = root as PanelContainer
	if panel != null:
		_classify(panel)
		_repaint(panel)
	for child: Node in root.get_children():
		apply_panels(child)


func _classify(panel: PanelContainer) -> void:
	if panel.has_meta(PANEL_TYPE_META):
		return
	var style: StyleBox = panel.get_theme_stylebox(PANEL_STYLEBOX)
	if style == null or style.resource_path.is_empty():
		return
	if style.resource_path.contains(DARK_STYLE_MARKER):
		panel.set_meta(PANEL_TYPE_META, PANEL_DARK)
	elif style.resource_path.contains(BASE_STYLE_MARKER):
		panel.set_meta(PANEL_TYPE_META, PANEL_BASE)


func _repaint(panel: PanelContainer) -> void:
	if not panel.has_meta(PANEL_TYPE_META):
		return
	# get_meta returns Variant, and a blind cast is not allowed here, so the shape
	# is checked before it is trusted.
	var raw_slot: Variant = panel.get_meta(PANEL_TYPE_META)
	if not raw_slot is String:
		return
	var slot: String = raw_slot
	match slot:
		PANEL_BASE:
			panel.add_theme_stylebox_override(PANEL_STYLEBOX, base_panel)
		PANEL_DARK:
			panel.add_theme_stylebox_override(PANEL_STYLEBOX, dark_panel)
		PANEL_HEADER:
			panel.add_theme_stylebox_override(PANEL_STYLEBOX, header_panel)


## Apply the shared selection and guide styling to a tree.
func style_tree(tree: Tree) -> void:
	if tree == null:
		return
	tree.add_theme_stylebox_override("selected", selection)
	tree.add_theme_stylebox_override("selected_focus", selection)
	tree.add_theme_color_override("guide_color", Color(1.0, 1.0, 1.0, GUIDE_ALPHA))


## Lay out a tree's columns and apply the shared styling in one call.
##
## Ratios rather than pixel widths, so the split survives a resize and a
## different editor scale.
func configure_tree(tree: Tree, titles: Array[String], ratios: Array[int]) -> void:
	if tree == null:
		return
	tree.hide_root = true
	tree.columns = maxi(titles.size(), 1)
	tree.set_column_titles_visible(not titles.is_empty() and not titles[0].is_empty())
	for index: int in titles.size():
		tree.set_column_title(index, titles[index])
		tree.set_column_expand(index, true)
		if index < ratios.size():
			tree.set_column_expand_ratio(index, ratios[index])
	style_tree(tree)


## The tab icon a dashboard tab shows, when its parent is a TabContainer.
func apply_tab_icon(tab: Control, icon: Texture2D) -> void:
	var container: TabContainer = tab.get_parent() as TabContainer
	if container == null or icon == null:
		return
	# Deferred: the parent may still be initialising when a child syncs.
	container.set_tab_icon.call_deferred(tab.get_index(), icon)
#endregion


## Greys the editor icons are recoloured from. They live here because this is
## the theme layer; outside it they read as hard-coded colours, which is
## exactly what they are anywhere else.
const ICON_NEUTRAL_GREYS: Array[String] = ["#e0e0e0", "#E0E0E0", "#ffffff", "#FFFFFF"]


#region Icon recolouring
## Recolour an SVG in memory to the editor's font colour and rasterise it at the
## user's UI scale, so icons stay legible on a 4K monitor and under both themes.
##
## Returns the plain resource outside the editor, where none of this applies.
static func recoloured_icon(path: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return load(path)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return load(path)

	var svg_text: String = file.get_as_text()
	file.close()

	var editor_theme: Theme = EditorInterface.get_editor_theme()
	var font_color: String = "#" + editor_theme.get_color(FONT_COLOR, EDITOR_THEME_TYPE).to_html(false)
	for grey: String in ICON_NEUTRAL_GREYS:
		svg_text = svg_text.replace(grey, font_color)

	var image: Image = Image.new()
	var editor_scale: float = EditorInterface.get_editor_scale()
	var err: int = image.load_svg_from_string(svg_text, editor_scale)
	if err == OK:
		return ImageTexture.create_from_image(image)

	return load(path)
#endregion


#region Icons
## The icon a caller asks for, recoloured to the editor's font colour.
static func icon(path: String) -> Texture2D:
	return recoloured_icon(path)
#endregion
