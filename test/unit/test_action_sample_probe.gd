## The sample, checked without a person watching it.
##
## The sample is the answer to "how do I use this", and a sample that quietly
## stopped working would be a wrong answer nobody notices - the engine's own
## suite would stay green while every page of the documentation lied.
##
## What runs here is the scene somebody presses play on, not a rig built for the
## test: `SampleWorld` is `main.tscn`'s root. F6.6 runs this same probe against a
## server and a client and asks whether the two agree.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

const SAMPLE_ROOT: String = "res://examples/action_sample"
const SAMPLE_SCENE: String = SAMPLE_ROOT + "/main.tscn"
## Not `project.godot`, and deliberately: Godot skips any directory containing
## a file by that name, so the sample would stop being compiled, stop
## registering its classes, and stop being checked by anything.
const SAMPLE_PROJECT: String = SAMPLE_ROOT + "/project.godot.standalone"

## What the sample's own project file has to say, spelled once here and read out
## of the addon's own settings rather than typed a second time.
const CUE_MANAGER_PATH: String = "res://addons/GAS_Engine/managers/gameplay_cue_manager.gd"
const SAMPLE_MAIN_SCENE: String = "res://main.tscn"

var world: SampleWorld = null


func before_each() -> void:
	world = SampleWorld.new()
	add_child_autofree(world)
	world.build()


func after_each() -> void:
	world = null


#region The seven demonstrations
## Every demonstration the phase names, run in order.
##
## One test rather than six, because they are one run: each leaves the world
## where the next expects it, and splitting them would mean six worlds built to
## check one sample.
func test_the_sample_demonstrates_everything_it_claims_to() -> void:
	var findings: Array[SampleProbe.Finding] = SampleProbe.run(world)

	assert_eq(findings.size(), 6, "every demonstration was attempted")
	for finding: SampleProbe.Finding in findings:
		assert_true(finding.held, finding.shown())


## The probe answers the same thing twice, which is what deterministic means.
##
## Run against a second world rather than the same one: a probe that only
## answered the same way when nothing had happened yet would not be telling
## anybody anything.
func test_the_probe_answers_the_same_way_every_time() -> void:
	var first: Array[SampleProbe.Finding] = SampleProbe.run(world)

	var again: SampleWorld = SampleWorld.new()
	add_child_autofree(again)
	again.build()
	var second: Array[SampleProbe.Finding] = SampleProbe.run(again)

	assert_eq(first.size(), second.size(), "the same demonstrations")
	for index: int in first.size():
		assert_eq(
			first[index].held, second[index].held,
			"'%s' answered the same both times" % first[index].what
		)
	assert_true(SampleProbe.all_held(first), "and everything held")
#endregion


#region What the sample is made of
## The sample reaches the engine rather than carrying a copy of it.
##
## The rule the phase states outright: nothing under `examples/` may be a second
## copy of anything under `addons/`. A sample that vendored the runtime would go
## stale the first time the engine changed and would teach whoever read it the
## version it was copied from.
func test_the_sample_carries_no_copy_of_the_runtime() -> void:
	var copied: Array[String] = []
	for path: String in GDScriptClassScan.scripts_under(SAMPLE_ROOT):
		var source: String = FileAccess.get_file_as_string(path)
		if source.contains("@meta_addon: GAS_Engine") and _declares_engine_class(source):
			copied.append(path)

	assert_eq(copied, [] as Array[String], "nothing under examples/ redeclares an engine class")


## The three abilities are granted as one set, and taken back as one.
func test_the_loadout_is_one_call_each_way() -> void:
	var character: SampleHero = world.dummies[0]

	assert_eq(character.asc.get_ability_specs().size(), 3, "three grants")
	character.unequip()
	assert_eq(character.asc.get_ability_specs().size(), 0, "and none after one call")


## The sample's cues are bound into the manager the whole project shares, and
## taken back out when the sample leaves.
func test_the_sample_binds_its_cues_and_gives_them_back() -> void:
	var manager: CueManagerScript = SampleCues.manager_from(world)
	assert_not_null(manager, "the addon's autoload is running")
	assert_eq(world.bound_cues, 3, "the sample's three cues were bound")
	assert_true(
		manager.catalog.scenes.has(SampleCues.STRIKE_IMPACT), "and the manager knows one"
	)

	SampleCues.unbind_from(manager)
	assert_false(
		manager.catalog.scenes.has(SampleCues.STRIKE_IMPACT),
		"and does not once the sample gives them back"
	)
#endregion


## The scene somebody presses play on is the one the probe runs.
##
## Two scenes would be a sample that passes its test and looks wrong: the check
## would be against a rig nobody sees, and the thing they see would be checked
## by nothing.
func test_the_scene_that_ships_is_the_one_that_is_checked() -> void:
	var scene: PackedScene = load(SAMPLE_SCENE)

	assert_not_null(scene, "the sample scene is where it says it is")
	var built: Node = scene.instantiate()
	add_child_autofree(built)

	assert_true(built is SampleWorld, "and its root is what the probe runs against")


## The sample's own project file asks for the autoload the addon needs.
##
## A sample somebody copies out and opens on its own is the first thing they
## run. If its project file has drifted from what the addon requires, the cues
## bind into nobody and the sample plays nothing - which looks exactly like an
## engine that does not work.
func test_the_sample_project_declares_the_autoload_the_addon_needs() -> void:
	var declared: String = FileAccess.get_file_as_string(SAMPLE_PROJECT)

	assert_true(declared.contains("[autoload]"), "it declares one")
	assert_true(
		declared.contains(CUE_MANAGER_PATH),
		"and it is the manager this project runs: %s" % CUE_MANAGER_PATH
	)
	assert_true(
		declared.contains(SAMPLE_MAIN_SCENE),
		"and it opens on the scene the sample ships"
	)
	assert_false(
		FileAccess.file_exists(SAMPLE_ROOT + "/project.godot"),
		"and there is no live project file here: Godot would skip the whole "
		+ "folder, and nothing in it would be compiled or checked again"
	)
#endregion


#region Getting there
## Whether a file declares a class the addon already declares.
##
## By the global class list rather than by reading names out of the source, so
## this asks the same question Godot does.
func _declares_engine_class(source: String) -> bool:
	for described: Dictionary in ProjectSettings.get_global_class_list():
		var where: String = described["path"]
		if not where.begins_with("res://addons/GAS_Engine/"):
			continue
		if source.contains("class_name %s " % described["class"]):
			return true
	return false
#endregion
