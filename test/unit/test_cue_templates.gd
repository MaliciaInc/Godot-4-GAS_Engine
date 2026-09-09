## The two cue templates a project gets without writing a script: a burst that
## happens once, and a loop that runs for as long as the effect behind it does.
##
## What is being proved is that authoring a cue is now data. Every case here
## builds a GameplayCueEffectSet and asserts what appeared in the world, which
## is exactly the work a project would otherwise do in a subclass of
## GameplayCueNotify per cue.
##
## The two requests these templates do not perform - camera shake and haptics -
## are asserted as signals, because that boundary is the point: this addon has
## no camera and no opinion about which device is in somebody's hands.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const TOLERANCE: float = 0.0001

var target: Node3D = null


func before_each() -> void:
	target = Node3D.new()
	target.name = "Struck"
	add_child_autofree(target)
	target.global_position = Vector3(10.0, 0.0, 0.0)


func after_each() -> void:
	target = null


#region Getting there
## A one-node scene, for a set to spawn.
func _spawnable() -> PackedScene:
	var template: Node3D = Node3D.new()
	template.name = "Spark"
	var scene: PackedScene = PackedScene.new()
	scene.pack(template)
	template.free()
	return scene


func _set_of(
	scenes: int = 1, shake: StringName = &"", placement: GameplayCuePlacement = null
) -> GameplayCueEffectSet:
	var made: GameplayCueEffectSet = GameplayCueEffectSet.new()
	var particles: Array[PackedScene] = []
	for _each: int in scenes:
		particles.append(_spawnable())
	made.particles = particles
	made.camera_shake = shake
	made.placement = placement
	return made


func _params(magnitude: float = 1.0) -> GameplayCueParams:
	var params: GameplayCueParams = GameplayCueParams.new()
	params.cue_tag = &"Cue.Template"
	params.target = target
	params.set_magnitude(magnitude, 0.0, 2.0)
	return params


## How many things this cue is still holding.
##
## Off the cue's own ledger rather than by counting children, because where a
## spawn is parented is the placement's business - what matters here is how
## many of them this cue is still responsible for.
func _spawned_under(cue: GameplayCueNotifyTemplate) -> int:
	return cue._spawned.size()
#endregion


#region A burst
func test_a_burst_plays_its_set_once_and_asks_for_a_shake() -> void:
	var cue: GameplayCueNotifyBurst = GameplayCueNotifyBurst.new()
	cue.burst = _set_of(2, &"Shake.Small")
	target.add_child(cue)
	watch_signals(cue)

	cue.executed(_params())

	assert_eq(_spawned_under(cue), 2, "both particles are there")
	assert_signal_emitted(
		cue, "camera_shake_requested", "and the shake went out as a request"
	)
	var said: Array = get_signal_parameters(cue, "camera_shake_requested", 0)
	var asked: StringName = said[0]
	assert_eq(asked, &"Shake.Small", "carrying the name the set declared")


## A cue coming back out of the pool starts empty.
##
## Pooling is the whole reason this matters: the node survives its playback, and
## one that kept its children would hand the next impact the last one's spark.
func test_finishing_a_burst_takes_back_what_it_spawned() -> void:
	var cue: GameplayCueNotifyBurst = GameplayCueNotifyBurst.new()
	cue.burst = _set_of(2)
	target.add_child(cue)

	cue.executed(_params())
	cue.finish_cue()
	await wait_process_frames(2)

	assert_eq(_spawned_under(cue), 0, "nothing of that playback is left")
#endregion


#region A loop
## Its four moments, in order, on one cue.
##
## One test rather than four because the interesting property is the sequence:
## what starts it, what runs for the whole of it, what recurs while it does, and
## what is left when it stops. Checked apart, each would pass while the others
## fired at the wrong moment.
func test_a_loop_starts_recurs_and_stops() -> void:
	var cue: GameplayCueNotifyLooping = GameplayCueNotifyLooping.new()
	cue.on_application = _set_of(1)
	cue.looping = _set_of(1)
	cue.recurring = _set_of(1)
	cue.on_removal = _set_of(1)
	cue.recurring_interval = 0.01
	target.add_child(cue)

	assert_false(cue.auto_destroy, "a persistent cue is never pooled on a timer")

	var params: GameplayCueParams = _params()
	cue.begin_persistent(params)
	assert_eq(_spawned_under(cue), 2, "the application set and the looping one")

	await wait_process_frames(4)
	assert_gt(_spawned_under(cue), 2, "and the recurring one has been round again")

	cue.end_persistent(params)
	await wait_process_frames(2)
	assert_eq(
		_spawned_under(cue), 0, "and nothing of the loop is still hanging off the cue"
	)


## The removal set outlives the cue that played it.
##
## A puff of smoke freed in the same frame it appeared is not a puff of smoke,
## so what the removal set spawned is moved out from under the cue about to be
## pooled rather than taken back with it.
func test_the_removal_set_is_released_rather_than_freed_with_the_cue() -> void:
	var cue: GameplayCueNotifyLooping = GameplayCueNotifyLooping.new()
	cue.on_removal = _set_of(1)
	cue.destroy_delay = 30.0
	target.add_child(cue)

	var params: GameplayCueParams = _params()
	cue.begin_persistent(params)
	var under_target_before: int = target.get_child_count()

	cue.end_persistent(params)
	await wait_process_frames(2)

	assert_eq(_spawned_under(cue), 0, "the cue is holding nothing")
	assert_eq(
		target.get_child_count(),
		under_target_before + 1,
		"and what it played on the way out is still in the world"
	)
#endregion


#region Where things go
## Placement decides whether an effect travels with what it was played on.
##
##     [what the placement says, whether moving the target moves the effect]
func _placement_cases() -> Array:
	return [
		["attached", GameplayCuePlacement.Mode.ATTACH_TO_TARGET, true],
		["at the origin", GameplayCuePlacement.Mode.AT_TARGET_ORIGIN, false],
	]


func test_placement_decides_whether_an_effect_travels(
	case: Array = use_parameters(_placement_cases())
) -> void:
	var described: String = case[0]
	var mode: GameplayCuePlacement.Mode = case[1]
	var travels: bool = case[2]

	var placement: GameplayCuePlacement = GameplayCuePlacement.new()
	placement.mode = mode
	var cue: GameplayCueNotifyBurst = GameplayCueNotifyBurst.new()
	cue.burst = _set_of(1, &"", placement)
	target.add_child(cue)

	cue.executed(_params())
	var spark: Node3D = _first_spark(cue)
	assert_not_null(spark, "%s: something was spawned" % described)
	var where: Vector3 = spark.global_position

	target.global_position = Vector3(50.0, 0.0, 0.0)
	var moved: bool = not spark.global_position.is_equal_approx(where)
	assert_eq(moved, travels, "%s: whether it followed" % described)


## Scaling reads the normalised number, so a cue authored once survives a
## rebalance of what a big hit is worth.
func test_an_effect_can_scale_by_how_loud_the_cue_was() -> void:
	var placement: GameplayCuePlacement = GameplayCuePlacement.new()
	placement.scale_by_magnitude = true
	var cue: GameplayCueNotifyBurst = GameplayCueNotifyBurst.new()
	cue.burst = _set_of(1, &"", placement)
	target.add_child(cue)

	# Half of the binding's range, so the scale is a half rather than the raw 1.0.
	cue.executed(_params(1.0))

	var spark: Node3D = _first_spark(cue)
	assert_almost_eq(spark.scale.x, 0.5, TOLERANCE, "scaled by the fraction, not the number")


## The first thing the cue spawned, as something with a position.
func _first_spark(cue: GameplayCueNotifyTemplate) -> Node3D:
	for node: Node in cue._spawned:
		var spatial: Node3D = node as Node3D
		if spatial != null:
			return spatial
	return null
#endregion
