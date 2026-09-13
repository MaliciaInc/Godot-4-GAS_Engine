## The whole way through, once: make an ability, give it something to do, run
## it, be told what is wrong, fix it, and see it in a running game.
##
## Eleven steps, and the reason they are one test rather than eleven is that the
## claim is about the joins. Every one of these works on its own - each has its
## own suite - and the gate is asking something else: that a person can get from
## an empty project to a running ability without falling into a gap between two
## tools that each work.
##
## The gaps are where this has actually broken. Creating left a script the
## grant pipeline could not take. The Output panel knew a line and threw it
## away. A loop in the middle of a body cost the whole Composer. None of those
## was visible from inside the piece that had it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

const SCRATCH: String = "user://gas_engine_test/walk_%d"
const MANA: StringName = &"mana"

## Where an ability lives in a project, for the step that asks the catalog
## what a call is. The suite writes under `user://`; the catalog reads a path.
const PROJECT_PATH: String = "res://abilities/walk.gd"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var made: int = 0
var script_path: String = ""
var scene_path: String = ""
var asset_path: String = ""


func before_each() -> void:
	fixture = Fixture.create("Walker")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://gas_engine_test")
	made += 1
	script_path = (SCRATCH % made) + ComposerAbilityTemplate.SCRIPT_SUFFIX
	scene_path = ComposerAbilityTemplate.scene_path_for(script_path)
	asset_path = (SCRATCH % made) + GameplayEffectAsset.RESOURCE_SUFFIX


func after_each() -> void:
	for path: String in [script_path, scene_path, asset_path]:
		DirAccess.remove_absolute(path)
	fixture = null
	asc = null


#region Getting there
## The scene, with whatever the inspector would have set on it.
##
## Loading, setting and repacking is exactly what editing a scene in the
## inspector does - so a step that says "configure the cost" is asserting the
## thing a person would do, not a shortcut past it.
func _configure(cost: GameplayAbilityCost, cooldown: GameplayEffect) -> PackedScene:
	var scene: PackedScene = ResourceLoader.load(
		scene_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var root: GameplayAbility = scene.instantiate() as GameplayAbility
	root.costs = [cost] as Array[GameplayAbilityCost]
	root.cooldown_effect = cooldown

	var repacked: PackedScene = PackedScene.new()
	repacked.pack(root)
	root.free()
	return repacked


## A body with a call short of a required argument, which is a draft.
func _draft_with_a_mistake() -> String:
	return FileAccess.get_file_as_string(script_path).replace(
		"\treturn true", "\tadd_tag()\n\treturn true"
	)
#endregion


#region The walk
## Steps one and two: creating leaves a script and a scene, and the scene is
## the thing an ASC can be given.
func test_step_one_creating_leaves_a_script_and_a_scene() -> void:
	var refusal: String = ComposerAbilityTemplate.create(script_path)

	assert_eq(refusal, "", "nothing refused it")
	assert_true(FileAccess.file_exists(script_path), "the script")
	assert_true(FileAccess.file_exists(scene_path), "and the scene beside it")


## Step three: an effect that lives in a file, so two abilities can share one.
func test_step_three_an_effect_asset_is_created_and_is_a_gameplay_effect() -> void:
	var refusal: String = GameplayEffectAsset.create(asset_path)

	assert_eq(refusal, "", "nothing refused it")
	var loaded: GameplayEffect = ResourceLoader.load(
		asset_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as GameplayEffect
	assert_not_null(loaded, "and it is a GameplayEffect")
	assert_eq(
		GameplayEffectAsset.missing_fields(loaded), [] as Array[StringName],
		"with everything on it an author needs"
	)


## Steps four, five and six: configure a cost and a cooldown on the ability that
## was just created, grant it, and run it.
func test_steps_four_to_six_configure_grant_and_run() -> void:
	ComposerAbilityTemplate.create(script_path)
	GameplayEffectAsset.create(asset_path)

	# The asset is the effect this ability is here to apply, authored in a file
	# so a second ability can apply the very same one.
	var payload: GameplayEffect = ResourceLoader.load(
		asset_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as GameplayEffect
	payload.modifiers = [EffectFactory.add(MANA, -10.0)] as Array[GameplayEffectModifier]
	assert_eq(ResourceSaver.save(payload, asset_path), OK, "the asset was configured")

	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = MANA
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = 10.0
	var cooldown: GameplayEffect = EffectFactory.granting(
		EffectFactory.duration([] as Array[GameplayEffectModifier], 5.0), [&"Cooldown.Walk"]
	)

	var handle: GameplayAbilityHandle = asc.give_ability(_configure(cost, cooldown))
	assert_true(handle.is_valid(), "granted")

	var before: float = asc.get_attribute_current(MANA)
	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)

	assert_true(result.is_ok(), "it ran")
	assert_almost_eq(
		asc.get_attribute_current(MANA), before, 0.0001,
		"and the template's body never commits, so nothing was paid yet"
	)


## Steps seven and eight: a draft that does not compile says what is wrong, and
## the row a person clicks knows both halves of where it is.
func test_steps_seven_and_eight_a_draft_says_what_is_wrong_and_where() -> void:
	ComposerAbilityTemplate.create(script_path)
	var draft: String = _draft_with_a_mistake()

	# Compiled under the path an ability lives at in a project, not the scratch
	# directory this suite writes to: the path is how the catalog knows which
	# class a bare call is on, so `add_tag()` is only short of an argument if the
	# file is somewhere an ability would be.
	var compiled: GameplayCompileService.Result = GameplayCompileService.compile(
		draft, PROJECT_PATH
	)

	assert_false(compiled.ready_to_run, "not ready to run")
	assert_eq(compiled.errors().size(), 1, "and one thing stops it")
	var found: GameplayCompileDiagnostic = compiled.errors()[0]
	assert_eq(found.code, GameplayCompileDiagnostic.MISSING_ARGUMENT, "said by its code")
	assert_gt(found.line, 0, "at a line")
	assert_gt(found.column, 0, "and a column past the indent")
	assert_false(found.node_id.is_empty(), "and on a card")


## Steps nine and ten: the draft is edited, saved, and reopened without loss.
##
## Byte for byte, including the doc comment the template wrote and the blank
## lines around it - which is the promise that makes the Composer safe to open
## a file with.
func test_steps_nine_and_ten_editing_saving_and_reopening_loses_nothing() -> void:
	ComposerAbilityTemplate.create(script_path)
	var document: ComposerDocument = ComposerDocument.new()
	document.open(FileAccess.get_file_as_string(script_path), script_path)

	var refusal: ComposerGraph.Diagnostic = document.insert(
		"\tcommit_ability()", document.after([] as Array[ComposerSpan])
	)
	assert_null(refusal, "the edit took")

	var saved: String = document.printed()
	var reopened: ComposerDocument = ComposerDocument.new()
	reopened.open(saved, script_path)

	assert_eq(reopened.printed(), saved, "reopened byte for byte")
	assert_true(saved.contains("commit_ability()"), "with the edit in it")
	assert_true(saved.contains("@tool"), "and everything the template wrote still there")


## Step eleven: a debugger looking at the running entity sees the grant, not
## the file it came from.
func test_step_eleven_the_debugger_sees_the_running_instance() -> void:
	ComposerAbilityTemplate.create(script_path)
	var handle: GameplayAbilityHandle = asc.give_ability(
		ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	)
	asc.add_tag(&"State.Walking")

	var seen: GasRuntimeSnapshot = GasRuntimeSnapshot.from_message(
		GasDebugChannel.snapshot_of(asc)
	)

	assert_eq(seen.asc_id, asc.get_instance_id(), "the entity in the running game")
	assert_not_null(seen.ability(handle.id), "with the grant on it, by handle")
	assert_gt(seen.tags.size(), 0, "and the tag it is carrying right now")
	assert_gt(seen.attributes.size(), 0, "and what its attributes are worth")
#endregion
