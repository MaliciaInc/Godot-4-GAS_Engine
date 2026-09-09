## What a person sees while aiming, and the promise that it comes off again.
##
## The property worth proving is a separation rather than a feature: a provider
## works out what is being aimed at and announces it, and something else decides
## whether to draw. So these tests check both halves - that the reticle follows
## what the provider says, and that no provider is holding one.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Bench = preload("res://test/fixtures/aiming_bench.gd")

const SPOT: Vector3 = Vector3(4.0, 0.0, -8.0)

var bench: AimingBench = null
var fixture: ASCFixture = null
var body: Node3D = null
var ability: GameplayAbility = null


## A provider that aims wherever the test tells it to.
##
## Its own class rather than a real one, because what is under test is the
## announcement rather than the physics: a provider that ran a query would make
## these assertions about the query.
class ScriptedProvider extends GameplayTargetProvider:
	var aims_at: Vector3 = Vector3.ZERO

	func _aim() -> GameplayAbilityTargetData:
		var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
		data.append_location(aims_at, Vector3.UP)
		return data


func before_each() -> void:
	bench = Bench.built(self)
	fixture = bench.fixture
	body = bench.body
	ability = bench.ability


func after_each() -> void:
	bench = null
	fixture = null
	body = null
	ability = null


#region Getting there
func _reticle_scene() -> PackedScene:
	var template: GameplayTargetReticle3D = GameplayTargetReticle3D.new()
	template.name = "Reticle"
	var scene: PackedScene = PackedScene.new()
	scene.pack(template)
	template.free()
	return scene


func _watching(provider: GameplayTargetProvider) -> AbilityTaskVisualizeTargeting:
	var task: AbilityTaskVisualizeTargeting = AbilityTaskVisualizeTargeting.create(
		ability, provider, _reticle_scene(), self
	)
	task.start()
	return task
#endregion


#region What a reticle is told
## The four things a reticle is told, each of which is a question the aiming
## already answered.
func test_a_reticle_is_told_where_whether_how_big_and_which_way() -> void:
	var reticle: GameplayTargetReticle3D = GameplayTargetReticle3D.new()
	add_child_autofree(reticle)
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_location(SPOT, Vector3.UP)

	reticle.follow(data)
	reticle.set_valid(false)
	reticle.set_radius(3.5)
	reticle.face_source(true)

	assert_eq(reticle.global_position, SPOT, "where it is pointing")
	assert_false(reticle.valid, "whether that is a legal place")
	assert_eq(reticle.radius, 3.5, "how big the area is")
	assert_true(reticle.faces_source, "and which way it looks")


## An aim with nothing located leaves the reticle where it was, which is what a
## person expects when they sweep past the edge of the world.
func test_an_aim_with_nowhere_in_it_leaves_the_reticle_alone() -> void:
	var reticle: GameplayTargetReticle3D = GameplayTargetReticle3D.new()
	add_child_autofree(reticle)
	reticle.global_position = SPOT

	reticle.follow(GameplayAbilityTargetData.new())

	assert_eq(reticle.global_position, SPOT, "it stayed where it was")
#endregion


#region The task owns the whole life of it
## The reticle appears, follows what the provider announces, and is gone when
## the task ends.
##
## All three in one test because they are one promise: something drawn by a task
## that outlived the task is exactly the failure this separation exists to make
## impossible.
func test_the_task_draws_what_the_provider_announces_and_takes_it_away() -> void:
	var provider: ScriptedProvider = ScriptedProvider.new()
	provider.begin(ability)
	var task: AbilityTaskVisualizeTargeting = _watching(provider)

	assert_not_null(task.reticle, "something was drawn")

	provider.aims_at = SPOT
	provider.update_preview()
	var drawn: GameplayTargetReticle3D = task.reticle as GameplayTargetReticle3D
	assert_eq(drawn.global_position, SPOT, "and it followed the aim")

	task.cancel(GameplayAbilityTask.CancelReason.MANUAL)
	assert_null(task.reticle, "and the task is holding nothing afterwards")


## Confirming ends the task, so the reticle goes with the confirmation rather
## than waiting for the ability to finish.
func test_confirming_takes_the_reticle_away() -> void:
	var provider: ScriptedProvider = ScriptedProvider.new()
	provider.begin(ability)
	var task: AbilityTaskVisualizeTargeting = _watching(provider)

	provider.confirm()

	assert_true(task.is_finished(), "the task is over")
	assert_null(task.reticle, "and nothing is left on screen")


## Nowhere to put it is not a failure. Aiming works perfectly well unseen, which
## is exactly what it does on a server.
func test_a_reticle_with_nowhere_to_go_does_not_fail_the_ability() -> void:
	var provider: ScriptedProvider = ScriptedProvider.new()
	provider.begin(ability)
	var task: AbilityTaskVisualizeTargeting = AbilityTaskVisualizeTargeting.create(
		ability, provider, null
	)

	task.start()

	assert_true(task.is_finished(), "the task finished rather than hanging")
	assert_null(task.reticle, "with nothing drawn")
#endregion


#region Nobody else holds one
## No provider anywhere in the addon keeps a reference to a reticle.
##
## Written as a check over the source rather than as a behaviour, because the
## thing being protected is a design boundary: a provider that grew a reticle
## field would still pass every behavioural test in this file, and would have
## made aiming and drawing one operation.
func test_no_provider_holds_a_reticle() -> void:
	var offenders: Array[String] = []
	for path: String in _provider_scripts():
		var source: String = FileAccess.get_file_as_string(path)
		if source.contains("Reticle"):
			offenders.append(path)

	assert_eq(
		offenders,
		[] as Array[String],
		"aiming announces what it aims at; something else decides to draw"
	)


func _provider_scripts() -> Array[String]:
	var found: Array[String] = ["res://addons/GAS_Engine/targeting/gameplay_target_provider.gd"]
	var directory: String = "res://addons/GAS_Engine/targeting/providers"
	for name: String in DirAccess.get_files_at(directory):
		if name.ends_with(".gd"):
			found.append(directory + "/" + name)
	return found
#endregion
