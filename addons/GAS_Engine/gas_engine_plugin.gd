## The editor plugin: dashboard, tag inspector, and one-time project seeding.
##
## `project.godot` declares the GameplayCueManager autoload directly so a clean
## checkout reaches its tests without an editor, and upstream's `_enable_plugin`
## registered the same autoload again - two authorities over one singleton. The
## registration here is idempotent, so enabling the plugin cannot produce a
## duplicate, but enabling it is a deliberate decision with its own tests, not a
## side effect.
##
## Seeding the default registry resources lives here rather than in
## project_settings.gd. Doing it there required preloading both registry
## scripts, and the tag registry preloads the generator, which preloads
## project_settings back: a preload cycle. Seeding is an editor concern anyway.
##
## @meta_addon: GAS_Engine
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends EditorPlugin

const CUE_MANAGER_NAME: String = "GameplayCueManager"
const CUE_MANAGER_PATH: String = "res://addons/GAS_Engine/managers/gameplay_cue_manager.gd"
const PLUGIN_DISPLAY_NAME: String = GASEngineProjectSettings.ADDON_NAME
const PLUGIN_ICON_PATH: String = "res://addons/GAS_Engine/icons/gas_engine.svg"

const DASHBOARD_SCENE: PackedScene = preload("res://addons/GAS_Engine/editor/gas_engine_dashboard.tscn")
const GameplayTagInspectorPlugin = preload("res://addons/GAS_Engine/gameplay_tag/gameplay_tag_inspector_plugin.gd")

## The autoload path as ProjectSettings stores it, for the idempotence check.
const AUTOLOAD_SETTING_PREFIX: String = "autoload/"


static func _autoload_setting_name() -> String:
	return AUTOLOAD_SETTING_PREFIX + CUE_MANAGER_NAME


static func _autoload_points_to_gas_engine() -> bool:
	var configured: String = ProjectSettings.get_setting(_autoload_setting_name(), "")
	return configured == "*" + CUE_MANAGER_PATH

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

## Whether this plugin is the one that added the cue manager autoload.
##
## Disabling GAS_Engine must never remove an autoload the project declared for
## itself. Upstream removed it unconditionally, so a project that had wired the
## singleton by hand lost it simply by turning the plugin off.
var _owns_cue_manager_autoload: bool = false

var _dashboard_instance: Control = null
var _tag_inspector: EditorInspectorPlugin = null


#region Plugin Lifecycle
## Register the autoload, unless the project already declares it.
##
## Upstream registered unconditionally, which produced a second authority over
## the same singleton for any project that had declared it itself.
## Whether enabling this plugin would have to add the autoload.
##
## False when the project already declares it: the plugin then adds nothing,
## owns nothing, and removes nothing when it is disabled. Exposed as its own
## question so that decision can be asked without an editor to enable a plugin
## in - which is the only place the enable path itself can run.
static func would_add_cue_manager_autoload() -> bool:
	return not ProjectSettings.has_setting(AUTOLOAD_SETTING_PREFIX + CUE_MANAGER_NAME)


func _enable_plugin() -> void:
	if not would_add_cue_manager_autoload():
		if (
			GASEngineProjectSettings.owns_cue_manager_autoload()
			and _autoload_points_to_gas_engine()
		):
			_owns_cue_manager_autoload = true
			return
		push_warning(
			"GAS_Engine: '" + CUE_MANAGER_NAME
			+ "' is already declared in project.godot; leaving that declaration alone."
		)
		_owns_cue_manager_autoload = false
		return

	add_autoload_singleton(CUE_MANAGER_NAME, CUE_MANAGER_PATH)
	_owns_cue_manager_autoload = true
	GASEngineProjectSettings.set_cue_manager_autoload_owned(true)


func _enter_tree() -> void:
	GASEngineProjectSettings.init_project_settings()
	_owns_cue_manager_autoload = (
		GASEngineProjectSettings.owns_cue_manager_autoload()
		and _autoload_points_to_gas_engine()
	)
	seed_default_registries()

	_tag_inspector = GameplayTagInspectorPlugin.new()
	add_inspector_plugin(_tag_inspector)

	_dashboard_instance = DASHBOARD_SCENE.instantiate()
	_dashboard_instance.visible = false
	EditorInterface.get_editor_main_screen().add_child(_dashboard_instance)
	_make_visible(false)


## Take back only what this plugin added.
func _disable_plugin() -> void:
	var persisted_owner: bool = GASEngineProjectSettings.owns_cue_manager_autoload()
	if not _owns_cue_manager_autoload and not persisted_owner:
		return

	if _autoload_points_to_gas_engine():
		remove_autoload_singleton(CUE_MANAGER_NAME)

	_owns_cue_manager_autoload = false
	GASEngineProjectSettings.set_cue_manager_autoload_owned(false)


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
	var path: String = GASEngineProjectSettings.get_registry_cue_path()
	if FileAccess.file_exists(path):
		return

	var absolute_dir: String = ProjectSettings.globalize_path(path.get_base_dir())
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_error("GAS_Engine: could not create cue registry directory: " + path.get_base_dir())
		return

	var registry: GameplayCueRegistry = GameplayCueRegistry.new()
	var save_error: Error = ResourceSaver.save(registry, path)
	if save_error != OK:
		push_error("GAS_Engine: could not seed cue registry: " + path)


func _seed_tag_registry() -> void:
	var path: String = GASEngineProjectSettings.get_registry_tag_path()
	var registry: GameplayTagRegistry = null

	if FileAccess.file_exists(path):
		registry = load(path) as GameplayTagRegistry
		if registry == null:
			push_error("GAS_Engine: tag registry is not a GameplayTagRegistry: " + path)
			return
	else:
		registry = GameplayTagRegistry.new()
		for tag: String in EXAMPLE_TAGS:
			var result: String = registry.add_tag(tag)
			if result.begins_with(GameplayTagRegistry.ERROR_PREFIX):
				push_error("GAS_Engine: could not seed example tag: " + result)
				return

		var absolute_dir: String = ProjectSettings.globalize_path(path.get_base_dir())
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
		if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
			push_error("GAS_Engine: could not create tag registry directory: " + path.get_base_dir())
			return

		var save_error: Error = ResourceSaver.save(registry, path)
		if save_error != OK:
			push_error("GAS_Engine: could not seed tag registry: " + path)
			return

	var generated_path: String = GASEngineProjectSettings.get_generated_tag_script_path()
	if not FileAccess.file_exists(generated_path):
		if not GameplayTagGenerator.generate_tags_file(registry.tags):
			push_error("GAS_Engine: could not seed generated gameplay tag script.")
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
