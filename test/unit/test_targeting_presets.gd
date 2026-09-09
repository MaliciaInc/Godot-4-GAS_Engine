## A whole aim authored as a list of steps, and the promise that it answers the
## same way twice.
##
## "Everything within five metres, that is an enemy, nearest first, first one"
## is four steps and no script. What is being proved is the machinery: that each
## step is handed what the last one found, in the order they were written, and
## that the answer does not depend on anything a second machine cannot
## reproduce.
##
## The steps that query physics are checked against the real physics server, the
## way the targeting suites are: a preset whose selecting step was stubbed would
## be a test of the list rather than of the aim.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")

const SIZE: float = 1.0
const ORIGIN: Vector3 = Vector3.ZERO
const NEAR: Vector3 = Vector3(3.0, 0.0, 0.0)
const FAR: Vector3 = Vector3(7.0, 0.0, 0.0)
const OUTSIDE: Vector3 = Vector3(40.0, 0.0, 0.0)
const ENEMY: StringName = &"Team.Enemy"

var caster: StaticBody3D = null
var caster_asc: AbilitySystemComponent = null


## A step that records the order it ran in, so a preset's sequence can be
## observed rather than inferred from its answer.
class RecordingStep extends GameplayTargetingTask:
	static var ran: Array[StringName] = []
	var label: StringName = &""

	func execute(
		input: GameplayAbilityTargetData, _source_asc: AbilitySystemComponent
	) -> GameplayAbilityTargetData:
		ran.append(label)
		return input


## A node of a particular kind, for the filter that keeps one kind.
##
## A script rather than a node type, because that is what the filter matches
## on: a class name is a string nobody checks, and a typo in one produces a
## step that quietly keeps nothing.
class MarkedNode extends Node3D:
	pass


## A step that answers with nothing at all, which a badly written one might.
class NullStep extends GameplayTargetingTask:
	func execute(
		_input: GameplayAbilityTargetData, _source_asc: AbilitySystemComponent
	) -> GameplayAbilityTargetData:
		return null


func before_each() -> void:
	RecordingStep.ran = [] as Array[StringName]
	caster = _actor("Caster", ORIGIN)
	caster_asc = AbilitySystemLocator.find_for_node(caster)


func after_each() -> void:
	caster = null
	caster_asc = null


#region Building a world
func _component() -> AbilitySystemComponent:
	var component: AbilitySystemComponent = AbilitySystemComponent.new()
	component.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	component.attribute_sets = [AttributeSetScript.new()]
	component.share_attributes = true
	return component


func _actor(actor_name: String, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = actor_name
	body.position = at
	body.collision_layer = 1
	body.add_child(_component())
	var holder: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = SIZE
	holder.shape = sphere
	body.add_child(holder)
	add_child_autofree(body)
	return body


func _enemy(actor_name: String, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = _actor(actor_name, at)
	AbilitySystemLocator.find_for_node(body).add_tag(ENEMY)
	return body


func _preset(steps: Array[GameplayTargetingTask]) -> GameplayTargetingPreset:
	var preset: GameplayTargetingPreset = GameplayTargetingPreset.new()
	preset.tasks = steps
	return preset


func _recording(label: StringName) -> RecordingStep:
	var step: RecordingStep = RecordingStep.new()
	step.label = label
	return step


func _enemies_only() -> TargetingFilterByTagQuery:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [ENEMY] as Array[StringName]
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	var step: TargetingFilterByTagQuery = TargetingFilterByTagQuery.new()
	step.query = query
	return step
#endregion


#region The list itself
## Steps run in the order they were written, each handed what the last found.
##
## Both halves: the sequence is observed from the steps themselves, and the
## carrying is observed from the answer - a preset that ran them in order but
## discarded each result would pass a test of only the first.
func test_steps_run_in_authored_order_each_handed_the_last_ones_answer() -> void:
	var preset: GameplayTargetingPreset = _preset(
		[
			_recording(&"first"),
			TargetingSelectSource.new(),
			_recording(&"second"),
		] as Array[GameplayTargetingTask]
	)

	var found: GameplayAbilityTargetData = preset.execute(caster_asc)

	assert_eq(
		RecordingStep.ran,
		[&"first", &"second"] as Array[StringName],
		"in the order they were written"
	)
	assert_eq(
		found.get_target_nodes(), [caster] as Array[Node], "and what the middle one found survived"
	)


## A preset with no steps answers an empty aim rather than nothing.
##
## So a caller never has to tell "aimed at nobody" apart from "did not run":
## both are an aim with nothing in it, and only one of those is a bug.
func test_an_empty_preset_answers_an_empty_aim() -> void:
	var found: GameplayAbilityTargetData = _preset(
		[] as Array[GameplayTargetingTask]
	).execute(caster_asc)

	assert_not_null(found, "it answered")
	assert_false(found.has_targets(), "with nobody in it")


## A step that answers with nothing does not take the aim with it.
##
## Carrying the null forward would make every later step check for it; dropping
## the aim would lose what the earlier ones found. Neither, so a badly written
## step costs its own contribution and nothing else.
func test_a_step_that_answers_with_nothing_leaves_the_aim_alone() -> void:
	var preset: GameplayTargetingPreset = _preset(
		[TargetingSelectSource.new(), NullStep.new()] as Array[GameplayTargetingTask]
	)

	var found: GameplayAbilityTargetData = preset.execute(caster_asc)

	assert_eq(
		found.get_target_nodes(), [caster] as Array[Node], "what was found is still there"
	)


## A null entry in the list is skipped, because an unfilled slot in an inspector
## array is an ordinary thing and not a reason to answer nothing.
func test_an_unfilled_step_is_skipped() -> void:
	var steps: Array[GameplayTargetingTask] = [null, TargetingSelectSource.new()]

	var found: GameplayAbilityTargetData = _preset(steps).execute(caster_asc)

	assert_eq(found.get_target_nodes(), [caster] as Array[Node], "the real step still ran")
#endregion


#region The four steps a real aim is made of
## Select, filter, sort and take, against the real physics server.
##
## One test rather than four because the property worth proving is the sequence:
## the sweep finds three, the filter drops the caster and the ally, and the sort
## keeps the nearer of the two enemies. Each step checked alone would pass while
## the ones after it operated on the wrong thing.
func test_an_area_of_enemies_nearest_first_keeps_the_nearest_one() -> void:
	var near: StaticBody3D = _enemy("NearEnemy", NEAR)
	_enemy("FarEnemy", FAR)
	_actor("Ally", Vector3(2.0, 0.0, 0.0))
	_actor("Bystander", OUTSIDE)
	await wait_physics_frames(2)

	var sweep: TargetingSelectAoe = TargetingSelectAoe.new()
	sweep.radius = 20.0
	var nearest: TargetingSortByDistance = TargetingSortByDistance.new()
	nearest.keep = 1

	var found: GameplayAbilityTargetData = _preset(
		[sweep, _enemies_only(), nearest] as Array[GameplayTargetingTask]
	).execute(caster_asc)

	assert_eq(
		found.get_target_nodes(),
		[near] as Array[Node],
		"the nearer of the two enemies, and nobody else"
	)


## The same preset, run twice on the same world, answers the same way.
##
## The property the whole layer exists for: a client and a server running one
## preset have to agree about what was aimed at, and a step that consulted a
## clock or a random number would make that impossible to check.
func test_the_same_preset_on_the_same_world_answers_the_same_way() -> void:
	_enemy("A", NEAR)
	_enemy("B", FAR)
	_enemy("C", Vector3(5.0, 0.0, 0.0))
	await wait_physics_frames(2)

	var sweep: TargetingSelectAoe = TargetingSelectAoe.new()
	sweep.radius = 20.0
	var preset: GameplayTargetingPreset = _preset(
		[sweep, _enemies_only(), TargetingSortByDistance.new()] as Array[GameplayTargetingTask]
	)

	var once: Array[Node] = preset.execute(caster_asc).get_target_nodes()
	var twice: Array[Node] = preset.execute(caster_asc).get_target_nodes()

	assert_eq(once.size(), 3, "all three enemies")
	assert_eq(twice, once, "and the same order both times")


## Sorting furthest-first is the same order read the other way.
func test_sorting_the_other_way_reverses_it() -> void:
	var near: StaticBody3D = _enemy("Near", NEAR)
	var far: StaticBody3D = _enemy("Far", FAR)
	await wait_physics_frames(2)

	var sweep: TargetingSelectAoe = TargetingSelectAoe.new()
	sweep.radius = 20.0
	var furthest: TargetingSortByDistance = TargetingSortByDistance.new()
	furthest.descending = true

	var found: GameplayAbilityTargetData = _preset(
		[sweep, _enemies_only(), furthest] as Array[GameplayTargetingTask]
	).execute(caster_asc)

	assert_eq(found.get_target_nodes(), [far, near] as Array[Node], "furthest first")


## Sorting is about actors and must not drop the place an earlier step found.
##
## A bolt that leaves a scorch mark is one aim carrying both: the actor takes
## the damage and the spot is where the mark goes.
func test_sorting_carries_the_place_an_earlier_step_found() -> void:
	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aimed.append_node(caster)
	aimed.append_location(FAR, Vector3.UP)

	var sorted: GameplayAbilityTargetData = TargetingSortByDistance.new().execute(
		aimed, caster_asc
	)

	assert_eq(sorted.get_target_nodes(), [caster] as Array[Node], "the actor is still there")
	assert_true(sorted.has_locations(), "and so is the spot")
#endregion


#region Filtering by what a thing is
## A class filter keeps the named kind, and inverted keeps everything else.
##
##     [what it is called, whether inverted, who should be left]
func _class_filter_cases() -> Array:
	return [["keeping the kind", false, 1], ["keeping everything else", true, 1]]


func test_a_class_filter_keeps_one_side_or_the_other(
	case: Array = use_parameters(_class_filter_cases())
) -> void:
	var described: String = case[0]
	var inverted: bool = case[1]
	var expected: int = case[2]

	var marked: MarkedNode = MarkedNode.new()
	add_child_autofree(marked)
	var plain: Node3D = Node3D.new()
	add_child_autofree(plain)
	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aimed.append_node(marked)
	aimed.append_node(plain)

	var step: TargetingFilterByClass = TargetingFilterByClass.new()
	step.required_script = MarkedNode
	step.invert = inverted

	var kept: Array[Node] = step.execute(aimed, caster_asc).get_target_nodes()

	assert_eq(kept.size(), expected, "%s: one of the two survived" % described)
	assert_eq(
		kept.has(marked), not inverted, "%s: and it was the right one" % described
	)


## A tag filter drops what has no ability system at all.
##
## A wall cannot be an enemy: it has no tags to answer with, and keeping it
## because it failed to disagree would put scenery in an aim about factions.
func test_a_tag_filter_drops_what_cannot_answer() -> void:
	var wall: Node3D = Node3D.new()
	add_child_autofree(wall)
	var aimed: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aimed.append_node(wall)

	var kept: Array[Node] = _enemies_only().execute(aimed, caster_asc).get_target_nodes()

	assert_eq(kept.size(), 0, "nothing that could not answer was kept")
#endregion
