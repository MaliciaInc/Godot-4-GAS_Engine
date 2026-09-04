## Enabling the plugin, and what it is allowed to do to somebody's project.
##
## The autoload is the one thing this plugin writes into a project it did not
## write, so every case is decided here rather than found out afterwards: it
## adds the singleton when nothing declares it, keeps its hands off a
## declaration the project made for itself, and says something out loud for
## exactly one situation - a name already taken by a different file.
##
## The warning is the reason this exists. It fired for every project that
## declared the singleton itself, which is the ordinary way to use this addon,
## so the message that means somebody has a real collision arrived looking
## identical to a message that meant nothing was wrong.
##
## Enabling a plugin happens inside an editor and this suite deliberately has
## none, so the decision is asked for directly. Every test puts the two
## settings back the way it found them - this project declares the singleton,
## and a test that left that changed would be editing the project it runs in.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Plugin = preload("res://addons/GAS_Engine/gas_engine_plugin.gd")

## The setting the ownership marker lives in.
const MARKER: String = GASEngineProjectSettings.PROJECT_SETTINGS_NAME_INTERNAL_CUE_MANAGER_OWNED

## A real script that is definitely not this addon's cue manager, under the
## name this addon wants.
const OTHER_PATH: String = "res://test/fixtures/cue_probe.gd"

var _autoload_was: Variant = null
var _marker_was: Variant = null


func before_each() -> void:
	_autoload_was = ProjectSettings.get_setting(Plugin.autoload_setting_name(), null)
	_marker_was = ProjectSettings.get_setting(MARKER, null)


## Put the project back. `null` erases, which is what a setting that was not
## there to begin with has to go back to.
func after_each() -> void:
	ProjectSettings.set_setting(Plugin.autoload_setting_name(), _autoload_was)
	ProjectSettings.set_setting(MARKER, _marker_was)


#region The four projects this can be enabled in
## Nothing declares the singleton.
func _absent() -> void:
	ProjectSettings.set_setting(Plugin.autoload_setting_name(), null)
	ProjectSettings.set_setting(MARKER, null)


## The canonical declaration, and the marker saying this plugin put it there.
func _owned() -> void:
	ProjectSettings.set_setting(
		Plugin.autoload_setting_name(),
		Plugin.AUTOLOAD_ENABLED_PREFIX + Plugin.CUE_MANAGER_PATH
	)
	ProjectSettings.set_setting(MARKER, true)


## The canonical declaration, put there by the project itself.
func _unowned() -> void:
	ProjectSettings.set_setting(
		Plugin.autoload_setting_name(),
		Plugin.AUTOLOAD_ENABLED_PREFIX + Plugin.CUE_MANAGER_PATH
	)
	ProjectSettings.set_setting(MARKER, null)


## The name taken by something that is not this addon's cue manager.
func _conflicting() -> void:
	ProjectSettings.set_setting(
		Plugin.autoload_setting_name(), Plugin.AUTOLOAD_ENABLED_PREFIX + OTHER_PATH
	)
	ProjectSettings.set_setting(MARKER, null)
#endregion


#region Which declaration counts as ours
## Only the exact canonical path, and only with the star. Anything else is
## somebody else's singleton, whatever the ownership marker happens to say.
func test_only_the_exact_canonical_path_is_recognised_as_ours() -> void:
	_owned()
	assert_true(
		Plugin.declares_gas_engine_cue_manager(), "the path this addon ships"
	)

	_conflicting()
	assert_false(
		Plugin.declares_gas_engine_cue_manager(), "a path this addon does not ship"
	)
#endregion


#region Case C: the project declared it itself
## The marker is the only thing that says whose it is. Without it the
## declaration belongs to whoever wrote project.godot, and adopting it would
## mean disabling the plugin took away a singleton it never added.
func test_a_declaration_the_project_made_is_not_adopted() -> void:
	_unowned()

	var plan: Plugin.Plan = Plugin.plan_for_cue_manager()

	assert_false(plan.adds, "nothing is added over it")
	assert_false(plan.owns, "and it is not taken over")


## This is the ordinary case, and the one the old warning fired on.
func test_a_declaration_the_project_made_is_not_worth_a_warning() -> void:
	_unowned()

	assert_eq(
		Plugin.plan_for_cue_manager().complaint, "", "the ordinary case says nothing"
	)


## The same file, declared without the star, is a singleton somebody switched
## off on purpose - not a collision, and not ours to switch back on.
func test_the_same_file_without_the_star_is_left_alone_quietly() -> void:
	ProjectSettings.set_setting(Plugin.autoload_setting_name(), Plugin.CUE_MANAGER_PATH)
	ProjectSettings.set_setting(MARKER, true)

	var plan: Plugin.Plan = Plugin.plan_for_cue_manager()

	assert_eq(plan.complaint, "", "the same file is not a different path")
	assert_false(plan.adds, "the declaration stands")
	assert_false(plan.owns, "and a singleton that is off is not ours to own")
#endregion


#region Case D: the name is taken by something else
func test_a_name_pointing_somewhere_else_is_not_replaced() -> void:
	_conflicting()

	assert_false(
		Plugin.plan_for_cue_manager().adds, "somebody else's declaration stands"
	)


func test_a_name_pointing_somewhere_else_is_not_adopted() -> void:
	_conflicting()

	assert_false(
		Plugin.plan_for_cue_manager().owns, "and it was never this plugin's to own"
	)


## Nothing this plugin owns, so disabling it takes nothing away.
func test_a_name_pointing_somewhere_else_is_not_removed_on_the_way_out() -> void:
	_conflicting()
	ProjectSettings.set_setting(MARKER, true)

	assert_false(
		Plugin.declares_gas_engine_cue_manager(),
		"a stale marker does not make somebody else's autoload removable"
	)


func test_a_name_pointing_somewhere_else_is_said_out_loud() -> void:
	_conflicting()

	assert_ne(Plugin.plan_for_cue_manager().complaint, "", "this one is worth saying")
#endregion


#region The whole decision, for every project
## Every project this plugin can be enabled in, and what enabling it does:
## whether the autoload is added, whether the plugin then owns it, and whether
## the person is told anything.
##
## One table rather than a test per case saying the same three sentences four
## times over, and the count below so an empty table cannot pass for a full one.
func _plans() -> Array:
	return [
		[_absent, true, true, false, "nothing declared it"],
		[_owned, false, true, false, "this plugin declared it"],
		[_unowned, false, false, false, "the project declared it"],
		[_conflicting, false, false, true, "somebody else declared it"],
	]


## The declaration and the ownership marker, written down so a before and an
## after can be compared as one thing.
func _settings_now() -> String:
	return "%s|%s" % [
		ProjectSettings.get_setting(Plugin.autoload_setting_name(), null),
		ProjectSettings.get_setting(MARKER, null),
	]


func test_every_project_gets_the_plan_it_should() -> void:
	var tried: Array = _plans()
	var checked: int = 0
	for row: Array in tried:
		var arrange: Callable = row[0]
		var adds: bool = row[1]
		var owns: bool = row[2]
		var spoken: bool = row[3]
		var described: String = row[4]
		arrange.call()

		var plan: Plugin.Plan = Plugin.plan_for_cue_manager()

		assert_eq(plan.adds, adds, "adds the autoload: " + described)
		assert_eq(plan.owns, owns, "owns it afterwards: " + described)
		assert_eq(
			not plan.complaint.is_empty(), spoken, "says something: " + described
		)
		checked += 1
	assert_eq(checked, tried.size(), "every project was tried")
	assert_gt(checked, 0, "and there were projects to try")


## Asking is a question, not a change. A decision that wrote the marker would
## make the second enable disagree with the first for no reason anybody could
## see.
func test_asking_changes_nothing_about_the_project() -> void:
	var tried: Array = _plans()
	var checked: int = 0
	for row: Array in tried:
		var arrange: Callable = row[0]
		var described: String = row[4]
		arrange.call()
		var before: String = _settings_now()

		Plugin.plan_for_cue_manager()

		assert_eq(_settings_now(), before, "nothing moved: " + described)
		checked += 1
	assert_eq(checked, tried.size(), "every project was tried")
	assert_gt(checked, 0, "and there were projects to try")
#endregion


#region What the rest of the plugin asks
## The question the smoke test asks is the same decision, not a second one.
func test_the_question_the_plugin_exposes_follows_the_same_decision() -> void:
	_absent()
	assert_true(Plugin.would_add_cue_manager_autoload(), "nothing declares it")

	_unowned()
	assert_false(Plugin.would_add_cue_manager_autoload(), "something already does")
#endregion
