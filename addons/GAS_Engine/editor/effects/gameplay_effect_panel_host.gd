## Puts the Gameplay Effect editor in the bottom panel, and shows it whatever
## effect the Inspector is editing.
##
## Held by the addon's one EditorPlugin rather than registered as a plugin of
## its own. It was its own plugin once, and nothing registered it, so the panel
## was never there. Answering `_handles()` from the addon's plugin instead would
## be worse: a plugin that handles an object is asked to be its main screen, and
## that plugin's main screen is the Composer. The Inspector announcing what it
## edits is the same moment, without handing the window to the wrong screen.
##
## Through `adopt` rather than `open`, because the Inspector already has the
## Resource in hand: loading it again by path would hand the panel a second copy,
## and the two would drift the moment either was edited.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GameplayEffectPanelHost extends RefCounted

const EDITOR_SCENE: String = "res://addons/GAS_Engine/editor/effects/gameplay_effect_editor.tscn"

## The bottom panel rather than a main screen tab, because an effect is edited
## beside the scene it is used in and a main screen would take the whole window
## for one Resource.
const PANEL_TITLE: String = "Gameplay Effect"

## The screen in the panel. Public so a test can stand one up without an editor.
var screen: GameplayEffectEditor = null

var _plugin: EditorPlugin = null
var _inspector: EditorInspector = null


## Build the screen, put it in the bottom panel, and follow the Inspector.
func attach(plugin: EditorPlugin, inspector: EditorInspector) -> bool:
	var scene: PackedScene = load(EDITOR_SCENE) as PackedScene
	if plugin == null or scene == null:
		return false
	screen = scene.instantiate() as GameplayEffectEditor
	if screen == null:
		return false
	_plugin = plugin
	_plugin.add_control_to_bottom_panel(screen, PANEL_TITLE)
	_inspector = inspector
	if _inspector != null:
		_inspector.edited_object_changed.connect(_on_edited_object_changed)
	return true


## Take the panel back out, and stop following the Inspector.
func detach() -> void:
	if _inspector != null and _inspector.edited_object_changed.is_connected(_on_edited_object_changed):
		_inspector.edited_object_changed.disconnect(_on_edited_object_changed)
	_inspector = null
	if screen != null:
		if _plugin != null:
			_plugin.remove_control_from_bottom_panel(screen)
		screen.queue_free()
	screen = null
	_plugin = null


## Show one effect in the panel. False when there is no panel or no effect.
func show_effect(effect: GameplayEffect) -> bool:
	if screen == null or effect == null:
		return false
	screen.document.adopt(effect)
	screen.refresh()
	return true


## The Inspector moved on. Anything but an effect leaves the panel showing what
## it showed: somebody clicking a node to see where an effect is used has not
## finished with the effect.
func _on_edited_object_changed() -> void:
	var effect: GameplayEffect = _inspector.get_edited_object() as GameplayEffect
	if show_effect(effect):
		_plugin.make_bottom_panel_item_visible(screen)
