## Puts the Gameplay Effect editor into Godot, and takes it back out.
##
## Its own EditorPlugin rather than more branches inside the addon's main one:
## the effect editor is one screen with one lifetime, and a plugin that owns
## several screens is a plugin where turning one off is a decision about the
## others.
##
## Opens what the inspector is looking at. An effect selected in the filesystem
## dock is the effect somebody wants to edit, and asking them to open it a
## second time in another dialog is asking them to say the same thing twice.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
extends EditorPlugin

const EDITOR_SCENE: String = (
	"res://addons/GAS_Engine/editor/effects/gameplay_effect_editor.tscn"
)

## Where the screen lives. The bottom panel rather than a main screen tab,
## because an effect is edited beside the scene it is used in and a main screen
## would take the whole window for one Resource.
const PANEL_TITLE: String = "Gameplay Effect"

var _screen: GameplayEffectEditor = null


func _enter_tree() -> void:
	var scene: PackedScene = load(EDITOR_SCENE) as PackedScene
	if scene == null:
		return
	_screen = scene.instantiate() as GameplayEffectEditor
	if _screen == null:
		return
	add_control_to_bottom_panel(_screen, PANEL_TITLE)


func _exit_tree() -> void:
	if _screen == null:
		return
	remove_control_from_bottom_panel(_screen)
	_screen.queue_free()
	_screen = null


## Whether this plugin wants to be the one editing the selected object.
func _handles(object: Object) -> bool:
	return object is GameplayEffect


## Show the effect the editor selected.
##
## Through `adopt` rather than `open`, because the inspector already has the
## Resource in hand: loading it again by path would hand the screen a second
## copy, and the two would drift the moment either was edited.
func _edit(object: Object) -> void:
	if _screen == null:
		return
	var effect: GameplayEffect = object as GameplayEffect
	if effect == null:
		return
	_screen.document.adopt(effect)
	_screen.refresh()
