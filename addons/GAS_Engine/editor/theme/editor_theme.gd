## The host editor's own theme, named.
##
## Godot's editor theme is addressed by string: a colour is `"font_color"` in
## type `"Editor"`, an icon is a name in `"EditorIcons"`. Those strings are the
## editor's vocabulary rather than this project's, and every surface drawn inside
## the editor needs the same handful of them. Spelled at each call site they
## would be a dozen copies of names only Godot gets to change.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GASEditorTheme extends RefCounted

#region The editor's own names
const EDITOR_THEME_TYPE: String = "Editor"
const EDITOR_ICON_THEME: String = "EditorIcons"

const FONT_COLOR: String = "font_color"
const SUCCESS_COLOR: String = "success_color"
const ERROR_COLOR: String = "error_color"
const PANEL_STYLEBOX: String = "panel"
const NORMAL_STYLEBOX: String = "normal"
const SEPARATION: String = "separation"
const FONT_SIZE: String = "font_size"

## An icon Godot ships. Used where drawing our own would be a second picture of
## something the editor already has one for.
const ICON_REMOVE: String = "Remove"
#endregion


#region Icons
## The greys this project's own SVGs are drawn in, so a recolour can find them.
##
## They live here because this is the theme layer. Anywhere else they would read
## as hard-coded colours, which is exactly what they would be.
const ICON_NEUTRAL_GREYS: Array[String] = ["#e0e0e0", "#E0E0E0", "#ffffff", "#FFFFFF"]


## An icon of ours, repainted in the editor's font colour.
##
## A fixed grey looks deliberate against one editor theme and wrong against the
## next, and whoever changed their theme is not who will be asked why the icon
## looks broken. Returns the plain resource outside the editor, where there is
## no theme to ask and none of this applies.
static func icon(path: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return load(path)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return load(path)
	var svg_text: String = file.get_as_text()
	file.close()

	var editor_theme: Theme = EditorInterface.get_editor_theme()
	if editor_theme == null:
		return load(path)
	var font_color: String = (
		"#" + editor_theme.get_color(FONT_COLOR, EDITOR_THEME_TYPE).to_html(false)
	)
	for grey: String in ICON_NEUTRAL_GREYS:
		svg_text = svg_text.replace(grey, font_color)

	var image: Image = Image.new()
	if image.load_svg_from_string(svg_text, EditorInterface.get_editor_scale()) != OK:
		return load(path)
	return ImageTexture.create_from_image(image)
#endregion
