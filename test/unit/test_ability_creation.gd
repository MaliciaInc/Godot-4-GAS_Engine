## What "create a new ability" has to leave behind for it to be usable.
##
## It left a GDScript, and a script is not something an ASC can be given.
## `give_ability()` takes a PackedScene and nothing else - an ability is a Node
## with authored state on it - so a person who had just written one had to go
## and build that scene by hand before anything could run it. Every project
## built the same scene the same way, which is a step the tool should have
## taken.
##
## So creating writes the pair, and the strongest assertion here is the last
## one: the scene it wrote is handed straight to `give_ability()` and the grant
## comes back real. Anything less proves a file exists, not that it is worth
## anything.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const SCRATCH: String = "user://gas_engine_test/creation_%d"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var made: int = 0
var script_path: String = ""
var scene_path: String = ""


func before_each() -> void:
	fixture = Fixture.create("Author")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://gas_engine_test")


func after_each() -> void:
	_discard()
	fixture = null
	asc = null


#region Getting there
## A pair of paths nothing has written to yet.
##
## Numbered per call, because loading a script Godot has already seen under
## that path answers with the one it remembers - and a second test would then
## be asserting about the first test's file.
func _fresh() -> String:
	made += 1
	script_path = (SCRATCH % made) + ComposerAbilityTemplate.SCRIPT_SUFFIX
	scene_path = ComposerAbilityTemplate.scene_path_for(script_path)
	return script_path


func _discard() -> void:
	if not script_path.is_empty():
		DirAccess.remove_absolute(script_path)
		DirAccess.remove_absolute(scene_path)
	script_path = ""
	scene_path = ""


func _write_something_at(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("# not an ability")
	file.close()
#endregion


#region What creating leaves behind
## Both files, named after each other.
func test_creating_an_ability_writes_the_script_and_the_scene() -> void:
	var refusal: String = ComposerAbilityTemplate.create(_fresh())

	assert_eq(refusal, "", "nothing refused it")
	assert_true(FileAccess.file_exists(script_path), "the script is there")
	assert_true(FileAccess.file_exists(scene_path), "and the scene beside it")


## The scene's root is the ability the script describes.
##
## Not a Node with a script bolted on: an instance of the script itself, which
## is what makes the grant pipeline recognise it.
func test_the_scene_root_is_the_ability_the_script_describes() -> void:
	ComposerAbilityTemplate.create(_fresh())

	var scene: PackedScene = load(scene_path) as PackedScene
	var root: Node = scene.instantiate()
	add_child_autofree(root)

	var attached: Resource = root.get_script()
	assert_true(root is GameplayAbility, "the root is an ability")
	assert_not_null(attached, "with a script on it")
	assert_eq(
		attached.resource_path, script_path, "and it is the script written beside it"
	)


## The whole point, asserted the only way that means anything.
func test_the_scene_it_wrote_can_be_granted_as_it_is() -> void:
	ComposerAbilityTemplate.create(_fresh())

	var handle: GameplayAbilityHandle = asc.give_ability(load(scene_path) as PackedScene)

	assert_true(handle.is_valid(), "the grant went through")
	assert_not_null(asc.get_ability_spec(handle), "and there is a spec behind it")


## And what it wrote actually runs.
func test_and_what_it_wrote_runs() -> void:
	ComposerAbilityTemplate.create(_fresh())
	var handle: GameplayAbilityHandle = asc.give_ability(load(scene_path) as PackedScene)

	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(handle)

	assert_true(result.is_ok(), "the template's own body returned true")
#endregion


#region Refusing, and refusing whole
## An output that is already there stops both halves, and the refusal names
## both of them.
##
## Either side, because a scene somebody had already built by hand is exactly
## the file this would otherwise walk over - and the old refusal never looked
## at it, because it did not know the scene existed.
##
##     [what is in the way, which of the two outputs was written first]
func _occupied() -> Array:
	return [
		["a script is already there", "script"],
		["a scene is already there", "scene"],
	]


func test_an_output_that_already_exists_stops_both_halves() -> void:
	var rows: Array = _occupied()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var which: String = row[1]

		_discard()
		_fresh()
		var occupied: String = script_path if which == "script" else scene_path
		var free_side: String = scene_path if which == "script" else script_path
		_write_something_at(occupied)

		var refusal: String = ComposerAbilityTemplate.create(script_path)

		assert_true(refusal.contains(script_path), "%s: the refusal names the script" % described)
		assert_true(refusal.contains(scene_path), "%s: and the scene" % described)
		assert_true(refusal.contains(occupied), "%s: and which one is in the way" % described)
		assert_false(
			FileAccess.file_exists(free_side), "%s: and the other side was not written" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "both sides were offered")


## A path Godot cannot resolve is refused before anything is written.
##
##     [what is wrong with it, the path]
func _uncreatable() -> Array:
	return [
		["no root at all", "abilities/fireball.gd"],
		["a root Godot does not have", "file:///abilities/fireball.gd"],
		["not a script", "user://gas_engine_test/fireball.txt"],
		["the scene rather than the script", "user://gas_engine_test/fireball.tscn"],
	]


func test_a_path_that_cannot_be_created_into_is_refused() -> void:
	var rows: Array = _uncreatable()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var path: String = row[1]

		var refusal: String = ComposerAbilityTemplate.create(path)

		assert_eq(refusal, ComposerAbilityTemplate.INVALID_PATH, "%s: refused" % described)
		assert_false(FileAccess.file_exists(path), "%s: and nothing was written" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every bad path was offered")
#endregion
