## The editor plugin: dashboard, tag inspector, and one-time project seeding.
##
## Not enabled in Phase 1. `project.godot` declares the GameplayCueManager
## autoload directly so a clean checkout reaches its tests without an editor,
## and upstream's `_enable_plugin` registered the same autoload again - two
## authorities over one singleton. The registration here is now idempotent, so
## enabling the plugin later cannot produce a duplicate, but re-enabling it is
## still a deliberate decision with its own tests, not a side effect.
##
## Seeding the default registry resources lives here rather than in
## project_settings.gd. Doing it there required preloading both registry
## scripts, and the tag registry preloads the generator, which preloads
## project_settings back: a preload cycle. Seeding is an editor concern anyway.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
extends EditorPlugin

const CUE_MANAGER_NAME: String = "GameplayCueManager"
const CUE_MANAGER_PATH: String = "res://addons/GodotGAS/managers/gameplay_cue_manager.gd"
const PLUGIN_DISPLAY_NAME: String = "GodotGAS"
const PLUGIN_ICON_PATH: String = "res://addons/GodotGAS/icons/godot_gas.svg"

const DASHBOARD_SCENE: PackedScene = preload("res://addons/GodotGAS/editor/godot_gas_dashboard.tscn")
const GameplayTagInspectorPlugin = preload("res://addons/GodotGAS/gameplay_tag/gameplay_tag_inspector_plugin.gd")
const GodotGasProjectSettings = preload("res://addons/GodotGAS/utilities/project_settings.gd")
const CueRegistry = preload("res://addons/GodotGAS/cues/gameplay_cue_registry.gd")
const TagRegistry = preload("res://addons/GodotGAS/gameplay_tag/gameplay_tag_registry.gd")

## The autoload path as ProjectSettings stores it, for the idempotence check.
const AUTOLOAD_SETTING_PREFIX: String = "autoload/"

## The tags a fresh tag registry is seeded with.
const EXAMPLE_TAGS: Array[String] = [
	"Example.Ability.Arrow.Impact",
	"Example.Ability.Arrow.Shoot",
	"Example.Ability.Heal.Triggered",
	"Example.Ability.Poison.Applied",
	"Example.Ability.Poison.Cast",
	"Example.Event.Damage.Critical",
	"Example.Event.Damage.Missed",
	"Example.Event.Damage.Normal",
	"Example.Event.Defend.Hit",
	"Example.State.Cooldown.Arrow",
	"Example.State.Cooldown.Poison",
]

var _dashboard_instance: Control = null
var _tag_inspector: EditorInspectorPlugin = null


#region Plugin Lifecycle
## Register the autoload, unless the project already declares it.
##
## Upstream registered unconditionally, which produced a second authority over
## the same singleton for any project that had declared it itself.
func _enable_plugin() -> void:
	if ProjectSettings.has_setting(AUTOLOAD_SETTING_PREFIX + CUE_MANAGER_NAME):
		push_warning(
			"GodotGAS: '" + CUE_MANAGER_NAME
			+ "' is already declared in project.godot; leaving that declaration alone."
		)
		return
	add_autoload_singleton(CUE_MANAGER_NAME, CUE_MANAGER_PATH)


func _enter_tree() -> void:
	GodotGasProjectSettings.init_project_settings()
	seed_default_registries()

	_tag_inspector = GameplayTagInspectorPlugin.new()
	add_inspector_plugin(_tag_inspector)

	_dashboard_instance = DASHBOARD_SCENE.instantiate()
	_dashboard_instance.visible = false
	EditorInterface.get_editor_main_screen().add_child(_dashboard_instance)
	_make_visible(false)


func _disable_plugin() -> void:
	remove_autoload_singleton(CUE_MANAGER_NAME)


func _exit_tree() -> void:
	if _tag_inspector != null:
		remove_inspector_plugin(_tag_inspector)
	if _dashboard_instance != null:
		_dashboard_instance.queue_free()
		_dashboard_instance = null
#endregion


#region Project seeding
## Create the default registry resources when they do not exist yet.
func seed_default_registries() -> void:
	_seed_cue_registry()
	_seed_tag_registry()


func _seed_cue_registry() -> void:
	var path: String = GodotGasProjectSettings.get_registry_cue_path()
	if FileAccess.file_exists(path):
		return
	var registry: GameplayCueRegistry = CueRegistry.new()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(registry, path)


func _seed_tag_registry() -> void:
	var path: String = GodotGasProjectSettings.get_registry_tag_path()
	if FileAccess.file_exists(path):
		return
	var registry: GameplayTagRegistry = TagRegistry.new()
	for tag: String in EXAMPLE_TAGS:
		registry.add_tag(tag)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(registry, path)
#endregion


#region Main Screen Integration
func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return PLUGIN_DISPLAY_NAME


func _get_plugin_icon() -> Texture2D:
	return DashboardTheme.icon(PLUGIN_ICON_PATH)


func _make_visible(next_visible: bool) -> void:
	if _dashboard_instance != null:
		_dashboard_instance.visible = next_visible
#endregion
