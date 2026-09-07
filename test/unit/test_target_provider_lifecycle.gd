## Choosing a target as something with a beginning and an end.
##
## Targeting was one call: ask the physics world, get an answer. That is right
## for a fireball that lands where it was aimed and wrong for everything a
## person aims by hand - a ground circle they drag, a cone they sweep, a unit
## they click. Those have a middle, and the middle is what breaks: an ability
## that ends while somebody is still aiming, a target that dies during the
## preview, a confirm that arrives twice.
##
## What is asserted here is that the middle ends. Exactly once, one way or the
## other, and never after the ability that started it is gone.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ABILITY_TAG: StringName = &"Ability.Aimed"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var ability: GameplayAbility = null

## What each signal said, in order, so "it finished once" is asserted rather
## than assumed.
var announced: Array[String] = []


func before_each() -> void:
	fixture = Fixture.create("Aimer")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	ability = AbilityFactory.give(asc, Probe.build(ABILITY_TAG)).per_actor_instance
	announced = []


func after_each() -> void:
	fixture = null
	asc = null
	ability = null


#region Getting there
func _watched() -> GameplayTargetProvider:
	var provider: GameplayTargetProvider = GameplayTargetProvider.new()
	provider.preview_changed.connect(
		func(_data: GameplayAbilityTargetData) -> void: announced.append("preview")
	)
	provider.confirmed.connect(
		func(_data: GameplayAbilityTargetData) -> void: announced.append("confirmed")
	)
	provider.cancelled.connect(func() -> void: announced.append("cancelled"))
	return provider


#endregion


#region A life with a beginning
## It starts idle and says nothing until it is begun.
func test_a_provider_says_nothing_until_it_is_begun() -> void:
	var provider: GameplayTargetProvider = _watched()

	assert_eq(provider.state, GameplayTargetProvider.State.IDLE, "idle")
	assert_false(provider.is_choosing(), "nobody is choosing")

	provider.update_preview()

	assert_eq(announced, [] as Array[String], "and it announced nothing")


## Beginning puts it in the middle, holding the ability it is choosing for.
func test_beginning_puts_it_in_the_middle() -> void:
	var provider: GameplayTargetProvider = _watched()

	provider.begin(ability)

	assert_eq(provider.state, GameplayTargetProvider.State.PREVIEWING, "previewing")
	assert_true(provider.is_choosing(), "and choosing")
	assert_same(provider.ability, ability, "for the ability that asked")


## Beginning twice is not a beginning.
##
## A provider already previewing has state a second begin() would discard, and
## the ability would be left waiting on a preview nobody is updating.
func test_beginning_twice_does_not_start_again() -> void:
	var provider: GameplayTargetProvider = _watched()
	provider.begin(ability)
	var other: GameplayAbility = AbilityFactory.give(
		asc, Probe.build(&"Ability.Other")
	).per_actor_instance

	provider.begin(other)

	assert_same(provider.ability, ability, "still choosing for the first one")


## Beginning for nothing is not beginning.
func test_beginning_for_no_ability_does_nothing() -> void:
	var provider: GameplayTargetProvider = _watched()

	provider.begin(null)

	assert_eq(provider.state, GameplayTargetProvider.State.IDLE, "still idle")
#endregion


#region Previewing
## Every preview is announced, and hands back what it announced.
func test_every_preview_is_announced_and_handed_back() -> void:
	var provider: GameplayTargetProvider = _watched()
	provider.begin(ability)

	var first: GameplayAbilityTargetData = provider.update_preview()
	provider.update_preview()

	assert_not_null(first, "an aim at nothing is still an answer")
	assert_eq(announced, ["preview", "preview"] as Array[String], "both were said")
	var last: GameplayAbilityTargetData = provider.update_preview()
	assert_same(provider.previewed, last, "and the newest is what it kept")
	assert_not_same(provider.previewed, first, "not the one from three previews ago")


## What is confirmed is what was last previewed.
func test_confirming_takes_what_was_last_previewed() -> void:
	var provider: FixedTargetProvider = FixedTargetProvider.new()
	var taken: Array[GameplayAbilityTargetData] = []
	provider.confirmed.connect(
		func(data: GameplayAbilityTargetData) -> void: taken.append(data)
	)
	provider.aimed_at = [fixture.owner] as Array[Node]
	provider.begin(ability)
	provider.update_preview()

	provider.confirm()

	assert_eq(taken.size(), 1, "confirmed once")
	assert_eq(taken[0].get_target_nodes(), [fixture.owner] as Array[Node], "with the aim")


## A target that dies during the preview is not in the next one.
##
## The case that motivates a preview being asked again rather than remembered:
## the world moves while somebody is aiming, and an answer from three frames ago
## is an answer about a target that may not be there.
func test_a_target_that_dies_during_the_preview_is_gone_from_the_next_one() -> void:
	var doomed: Node = Node.new()
	add_child(doomed)
	var provider: FixedTargetProvider = FixedTargetProvider.new()
	provider.aimed_at = [doomed] as Array[Node]
	provider.begin(ability)
	assert_eq(provider.update_preview().get_target_nodes().size(), 1, "aimed at it")

	doomed.free()
	provider.aimed_at = [] as Array[Node]

	assert_eq(provider.update_preview().get_target_nodes().size(), 0, "and now at nothing")
#endregion


#region It ends exactly once
## It ends once, whatever is asked of it afterwards.
##
## One table over every order two endings can arrive in, because the point is
## the same each time and writing it four ways is four places for one of them to
## start answering differently.
##
##     [what was asked, in order, what it ends as]
func _endings() -> Array:
	return [
		["confirmed, then confirmed again", ["confirm", "confirm"], "confirmed"],
		["cancelled, then cancelled again", ["cancel", "cancel"], "cancelled"],
		["confirmed, then cancelled", ["confirm", "cancel"], "confirmed"],
		["cancelled, then confirmed", ["cancel", "confirm"], "cancelled"],
	]


func test_a_provider_ends_exactly_once() -> void:
	var rows: Array = _endings()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var asked: Array = row[1]
		var stays: String = row[2]

		before_each()
		var provider: GameplayTargetProvider = _watched()
		provider.begin(ability)

		for which: String in asked:
			if which == "confirm":
				provider.confirm()
			else:
				provider.cancel()

		assert_eq(announced, [stays] as Array[String], "%s: one ending" % described)
		assert_false(provider.is_choosing(), "%s: and it is over" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every order was offered")


## Cancelling one that never started is safe.
##
## An ability ending cancels whatever it was waiting on without first asking
## whether that thing had answered, so a cancel that threw would make the
## ordinary teardown of every targeted ability something to be careful about.
func test_cancelling_one_that_never_started_is_safe() -> void:
	var provider: GameplayTargetProvider = _watched()

	provider.cancel()

	assert_eq(provider.state, GameplayTargetProvider.State.CANCELLED, "cancelled")
	assert_eq(announced, ["cancelled"] as Array[String], "and said so")


## Once it has ended it lets go of the ability, and previews nothing more.
func test_an_ended_provider_lets_go_and_previews_nothing_more() -> void:
	var provider: GameplayTargetProvider = _watched()
	provider.begin(ability)
	provider.confirm()
	announced = []

	provider.update_preview()

	assert_null(provider.ability, "it is holding nothing")
	assert_eq(announced, [] as Array[String], "and announcing nothing")
#endregion


#region The join with the ability that is aiming
## What a provider confirms is submitted the way any target data is.
##
## Which means a task already waiting on `wait_target_data()` hears it without
## knowing a provider was involved, and a game that aims some other way keeps
## working unchanged.
func test_what_a_provider_confirms_reaches_the_ability() -> void:
	ability.is_active = true
	var waiting: AbilityTaskWaitTargetData = ability.wait_target_data()
	var provider: FixedTargetProvider = FixedTargetProvider.new()
	provider.aimed_at = [fixture.owner] as Array[Node]

	ability.aim_with(provider)
	provider.update_preview()
	provider.confirm()

	assert_true(waiting.is_finished(), "the task that was waiting was answered")
	assert_eq(
		waiting.target_data.get_target_nodes(), [fixture.owner] as Array[Node],
		"with what the provider aimed at"
	)


## An ability that ends calls off whatever it was aiming with.
##
## The bug this lifecycle exists for: a preview left on screen for an ability
## that is over, and something waiting on a confirm that is never coming.
func test_an_ability_that_ends_calls_off_its_providers() -> void:
	ability.is_active = true
	var provider: GameplayTargetProvider = _watched()
	ability.aim_with(provider)
	assert_true(provider.is_choosing(), "aiming")

	ability.end_ability()

	assert_eq(provider.state, GameplayTargetProvider.State.CANCELLED, "called off")
	assert_eq(announced, ["cancelled"] as Array[String], "and said so once")


## An ability that is not running does not start aiming.
func test_an_ability_that_is_not_running_does_not_start_aiming() -> void:
	var provider: GameplayTargetProvider = _watched()

	ability.aim_with(provider)

	assert_eq(provider.state, GameplayTargetProvider.State.IDLE, "nothing began")
#endregion


#region What a machine that owns the game will take
## A claim about nothing is refused.
##
##     [what is wrong with the claim, whether it is accepted]
func _claims() -> Array:
	return [
		["nothing at all", "null", false],
		["an empty aim", "empty", false],
		["a target that is gone", "freed", false],
		["a target that is there", "real", true],
	]


func test_only_a_claim_it_can_check_is_accepted() -> void:
	var rows: Array = _claims()
	var checked: int = 0
	var provider: GameplayTargetProvider = GameplayTargetProvider.new()
	for row: Array in rows:
		var described: String = row[0]
		var which: String = row[1]
		var accepted: bool = row[2]

		var claim: GameplayAbilityTargetData = null
		if which != "null":
			claim = GameplayAbilityTargetData.new()
		if which == "real":
			claim.append_node(fixture.owner)
		if which == "freed":
			var doomed: Node = Node.new()
			add_child(doomed)
			claim.append_node(doomed)
			doomed.free()

		assert_eq(
			provider.validate_authoritative(claim, asc), accepted,
			"%s: accepted?" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every claim was offered")


## And a claim from nobody is refused whatever it says.
func test_a_claim_from_no_component_is_refused() -> void:
	var provider: GameplayTargetProvider = GameplayTargetProvider.new()
	var claim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	claim.append_node(fixture.owner)

	assert_false(provider.validate_authoritative(claim, null), "nobody claimed it")
#endregion


#region The four the phase names
## Each of the four carries the request it aims.
##
## Written out rather than looped: the type of each request is the point, and a
## loop would have to widen them to a common type to hold them - which is the
## one thing that would stop the compiler checking what this is about.
func test_all_four_providers_carry_the_request_they_aim() -> void:
	assert_not_null(GameplayRaycastTargetProvider2D.new().request, "a 2D ray")
	assert_not_null(GameplayRaycastTargetProvider3D.new().request, "a 3D ray")
	assert_not_null(GameplayOverlapTargetProvider2D.new().request, "a 2D sweep")
	assert_not_null(GameplayOverlapTargetProvider3D.new().request, "a 3D sweep")


## And each asks the physics service rather than doing physics itself.
##
##     [what it aims, the file, the call it makes]
func _providers() -> Array:
	var at: String = "res://addons/GAS_Engine/targeting/providers/%s.gd"
	return [
		["a 2D ray", at % "gameplay_raycast_target_provider_2d", "raycast_2d"],
		["a 3D ray", at % "gameplay_raycast_target_provider_3d", "raycast_3d"],
		["a 2D sweep", at % "gameplay_overlap_target_provider_2d", "overlap_2d"],
		["a 3D sweep", at % "gameplay_overlap_target_provider_3d", "overlap_3d"],
	]


func test_every_provider_asks_the_service_rather_than_the_world() -> void:
	var rows: Array = _providers()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var at: String = row[1]
		var call_made: String = row[2]

		var source: String = FileAccess.get_file_as_string(at)

		assert_false(source.is_empty(), "%s: the provider is there" % described)
		assert_true(
			source.contains("GameplayTargetingService.%s(" % call_made),
			"%s: asks the service" % described
		)
		assert_false(
			source.contains("direct_space_state"),
			"%s: and never does the physics itself" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "all four were offered")


## A provider whose ability is in no world aims at nothing rather than failing.
##
## Which is what a headless test is, and what an ability on a component that has
## been taken out of the tree is.
func test_a_provider_with_no_world_aims_at_nothing() -> void:
	var provider: GameplayRaycastTargetProvider3D = GameplayRaycastTargetProvider3D.new()
	provider.begin(ability)

	var found: GameplayAbilityTargetData = provider.update_preview()

	assert_false(found.has_targets(), "nothing to aim at, and nothing thrown")


## The physics service knows nothing about aiming over time.
##
## Its whole value is being answerable without a mouse, a camera or a frame -
## put input in it and every physics question this engine asks stops being
## provable.
func test_the_physics_service_never_learned_about_input() -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://addons/GAS_Engine/targeting/gameplay_targeting_service.gd"
	)

	assert_false(source.is_empty(), "the service was read")
	for named: String in ["Input.", "get_viewport", "Camera2D", "Camera3D", "get_global_mouse"]:
		assert_false(source.contains(named), "it never reaches for %s" % named)
#endregion
