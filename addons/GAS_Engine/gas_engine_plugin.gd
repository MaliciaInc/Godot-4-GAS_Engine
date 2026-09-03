## The editor plugin: dashboard, Ability Composer, tag inspector, and one-time
## project seeding.
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
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends EditorPlugin

const CUE_MANAGER_NAME: String = "GameplayCueManager"
const CUE_MANAGER_PATH: String = "res://addons/GAS_Engine/managers/gameplay_cue_manager.gd"
const PLUGIN_DISPLAY_NAME: String = GASEngineProjectSettings.ADDON_NAME
const PLUGIN_ICON_PATH: String = "res://addons/GAS_Engine/icons/gas_engine.svg"

const DASHBOARD_SCENE: PackedScene = preload("res://addons/GAS_Engine/editor/gas_engine_dashboard.tscn")

## The screen names itself; the menu that opens it says the same word by
## reading it rather than by agreeing to spell it the same way.
const COMPOSER_MENU: String = ComposerTopBar.COMPOSER_TAB
const DASHBOARD_MENU: String = "GAS_Engine Dashboard"
const SCRIPT_SCREEN: String = "Script"
const SCRIPT_FILTER: String = "*.gd"
const SCRIPT_FILTER_NAME: String = "GDScript"
## What the log says when the Composer was asked for and had nothing to draw.
##
## It carries the way out, not just the complaint. It also reads differently
## from the bare "GAS_Engine: %s" it replaced, on purpose: that line was
## identical before and after the screen learned to answer, so somebody reading
## the console could not tell a fixed plugin from a stale one.
const COMPOSER_REFUSED: String = (
	"GAS_Engine: the Ability Composer has nothing to draw - %s. Open an ability "
	+ "in the Script editor, then choose Ability Composer again."
)
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
var _composer_instance: ComposerScreen = null
var _tag_inspector: EditorInspectorPlugin = null

## Which of the two the main screen shows when it is asked to appear.
##
## The Composer and the dashboard share one main screen because a plugin has one
## to share. Remembering which was last asked for is what lets the Code chip
## leave for the script editor and the person come back to the ability they were
## looking at, rather than to a dashboard they did not ask for - the two views
## are meant to feel like one thing seen two ways.
var _showing_composer: bool = false


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

	_composer_instance = ComposerScreen.new()
	_composer_instance.visible = false
	_composer_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	_composer_instance.code_requested.connect(_on_code_requested)
	_composer_instance.open_requested.connect(_ask_for_an_ability)
	EditorInterface.get_editor_main_screen().add_child(_composer_instance)

	add_tool_menu_item(COMPOSER_MENU, _open_composer)
	add_tool_menu_item(DASHBOARD_MENU, _open_dashboard)
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
	remove_tool_menu_item(COMPOSER_MENU)
	remove_tool_menu_item(DASHBOARD_MENU)
	if _tag_inspector != null:
		remove_inspector_plugin(_tag_inspector)
	if _dashboard_instance != null:
		_dashboard_instance.queue_free()
		_dashboard_instance = null
	if _composer_instance != null:
		_composer_instance.queue_free()
		_composer_instance = null
#endregion


#region The Ability Composer
## Draw whatever ability the script editor currently has open.
##
## The script editor is asked rather than a picker of our own: a person who has
## an ability open and wants to see it drawn has already said which one, and
## making them say it again in a dialog is a step that exists only because the
## tool did not look.
func _open_composer() -> void:
	var script: Script = EditorInterface.get_script_editor().get_current_script()
	var opened: ComposerHost.Opened = ComposerHost.open(
		script.resource_path if script != null else ""
	)
	if not opened.is_ok():
		# Said where the person is looking, not only in the console. The warning
		# stays for the log, but the Output dock is not where somebody who just
		# chose Ability Composer is looking, and an unchanged main screen reads
		# as the menu item doing nothing at all.
		push_warning(COMPOSER_REFUSED % opened.refusal)
		_showing_composer = true
		_composer_instance.show_refusal(opened.refusal)
		EditorInterface.set_main_screen_editor(PLUGIN_DISPLAY_NAME)
		_make_visible(true)
		return

	_showing_composer = true
	_composer_instance.open(opened.source, opened.graph.source_path)
	EditorInterface.set_main_screen_editor(PLUGIN_DISPLAY_NAME)
	_make_visible(true)


func _open_dashboard() -> void:
	_showing_composer = false
	EditorInterface.set_main_screen_editor(PLUGIN_DISPLAY_NAME)
	_make_visible(true)


## Choose an ability to draw, without going to find it first.
##
## The Composer draws whatever the Script editor has open, which is right when
## somebody is already looking at an ability and wrong as the only way in: a
## person who picks Ability Composer from the Tools menu has asked for the
## Composer, not for a lecture about what they should have opened.
func _ask_for_an_ability() -> void:
	var picker: EditorFileDialog = EditorFileDialog.new()
	picker.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	picker.access = EditorFileDialog.ACCESS_RESOURCES
	picker.add_filter(SCRIPT_FILTER, SCRIPT_FILTER_NAME)
	picker.file_selected.connect(_draw_ability_at)
	picker.canceled.connect(picker.queue_free)
	EditorInterface.get_base_control().add_child(picker)
	picker.popup_file_dialog()


## Draw the file that was chosen, or say why it cannot be drawn - on the screen
## the person is already looking at, which is the Composer.
func _draw_ability_at(source_path: String) -> void:
	var opened: ComposerHost.Opened = ComposerHost.open(source_path)
	if not opened.is_ok():
		push_warning(COMPOSER_REFUSED % opened.refusal)
		_composer_instance.show_refusal(opened.refusal)
		return
	_composer_instance.open(opened.source, opened.graph.source_path)


## The Code chip: the same ability, in the editor that shows it as text.
##
## The ability stays loaded here, so coming back to this screen shows what the
## person left rather than starting them over. They are two views of one file,
## and neither is a copy of the other.
func _on_code_requested(source_path: String) -> void:
	if not source_path.is_empty():
		var script: Script = load(source_path) as Script
		if script != null:
			EditorInterface.edit_script(script)
	EditorInterface.set_main_screen_editor(SCRIPT_SCREEN)
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
		_dashboard_instance.visible = next_visible and not _showing_composer
	if _composer_instance != null:
		_composer_instance.visible = next_visible and _showing_composer
#endregion
