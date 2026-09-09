## When an aim is finished, who decided, and what a server can refuse.
##
## Four answers to the first question, and they are genuinely different: a
## snap-to-nearest that fires the moment it has anybody, a reticle somebody says
## yes to, a charge that completes on its own terms, and a chain that picks one
## target after another and keeps going. Every case here is the same provider
## under a different policy, because what is being proved is that they disagree.
##
## Split from test_target_provider_lifecycle.gd, which is about the states a
## provider moves through. This is about who moves it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Bench = preload("res://test/fixtures/aiming_bench.gd")

const SPOT: Vector3 = Vector3(3.0, 0.0, 0.0)
const FAR: Vector3 = Vector3(500.0, 0.0, 0.0)

var bench: AimingBench = null
var fixture: ASCFixture = null
var body: Node3D = null
var ability: GameplayAbility = null


## A provider that aims at whatever the test put in front of it.
class ScriptedProvider extends GameplayTargetProvider:
	var aims_at_a_place: bool = true

	func _aim() -> GameplayAbilityTargetData:
		var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
		if aims_at_a_place:
			data.append_location(SPOT, Vector3.UP)
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
func _aiming(policy: GameplayTargetProvider.Confirmation) -> ScriptedProvider:
	var provider: ScriptedProvider = ScriptedProvider.new()
	provider.confirmation = policy
	provider.begin(ability)
	return provider
#endregion


#region Who decides
## An instant aim is over the first time it has anything.
##
## And not before: an aim with nothing in it is still an aim, and one that
## confirmed on empty would fire the moment it started.
func test_an_instant_aim_confirms_itself_once_it_has_something() -> void:
	var provider: ScriptedProvider = _aiming(GameplayTargetProvider.Confirmation.INSTANT)
	provider.aims_at_a_place = false
	var taken: Array[GameplayAbilityTargetData] = []
	provider.confirmed.connect(
		func(data: GameplayAbilityTargetData) -> void: taken.append(data)
	)

	provider.update_preview()
	assert_true(provider.is_choosing(), "nothing to confirm yet")

	provider.aims_at_a_place = true
	var answer: GameplayAbilityTargetData = provider.update_preview()

	assert_eq(taken.size(), 1, "it confirmed itself")
	assert_true(answer.has_locations(), "and answered with what it took")
	assert_false(provider.is_choosing(), "and stopped")


## A user-confirmed aim waits, however much it is aimed.
func test_a_user_confirmed_aim_waits_to_be_told() -> void:
	var provider: ScriptedProvider = _aiming(
		GameplayTargetProvider.Confirmation.USER_CONFIRMED
	)

	provider.update_preview()
	provider.update_preview()
	assert_true(provider.is_choosing(), "still aiming")

	provider.confirm()
	assert_false(provider.is_choosing(), "until somebody said yes")


## A custom aim ends on its own first yes, like every other kind but the multi.
func test_a_custom_aim_ends_on_its_one_answer() -> void:
	var provider: ScriptedProvider = _aiming(GameplayTargetProvider.Confirmation.CUSTOM)

	provider.update_preview()
	provider.confirm()

	assert_false(provider.is_choosing(), "one answer, and it is over")


## A multi aim answers and keeps aiming.
##
## The state is the half that matters: a provider that emitted twice but stopped
## previewing would have handed the second answer out of a finished aim, and
## nothing after it would work.
func test_a_multi_aim_answers_more_than_once_and_keeps_going() -> void:
	var provider: ScriptedProvider = _aiming(
		GameplayTargetProvider.Confirmation.CUSTOM_MULTI
	)
	var taken: Array[GameplayAbilityTargetData] = []
	provider.confirmed.connect(
		func(data: GameplayAbilityTargetData) -> void: taken.append(data)
	)

	provider.update_preview()
	provider.confirm()
	provider.update_preview()
	provider.confirm()

	assert_eq(taken.size(), 2, "two answers")
	assert_true(provider.is_choosing(), "and it is still aiming")

	provider.cancel()
	assert_false(provider.is_choosing(), "until something stops it")
#endregion


#region What a server can refuse
## A radius provider refuses a claim about somebody outside its own circle.
func test_a_radius_provider_refuses_a_target_outside_its_circle() -> void:
	var struck: Node3D = Node3D.new()
	add_child_autofree(struck)
	struck.global_position = FAR

	var provider: GameplayRadiusProvider3D = GameplayRadiusProvider3D.new()
	provider.request.center = Vector3.ZERO
	provider.request.radius = 5.0
	var claim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	claim.append_node(struck)

	assert_false(
		provider.validate_authoritative(claim, fixture.asc),
		"nobody at five hundred metres was inside a five metre circle"
	)

	struck.global_position = Vector3(1.0, 0.0, 0.0)
	var near: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	near.append_node(struck)
	assert_true(
		provider.validate_authoritative(near, fixture.asc), "and somebody inside it is"
	)


## A ground trace answers with a place and never with an actor, so a claim that
## names one is a claim it could not have produced.
func test_a_ground_trace_refuses_a_claim_that_names_an_actor() -> void:
	var struck: Node3D = Node3D.new()
	add_child_autofree(struck)

	var provider: GameplayGroundTraceProvider3D = GameplayGroundTraceProvider3D.new()
	var claim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	claim.append_node(struck)

	assert_false(
		provider.validate_authoritative(claim, fixture.asc),
		"a trace answers with a spot on the ground"
	)


## A placement refuses a spot further away than it was authored to allow.
func test_a_placement_refuses_a_spot_out_of_range() -> void:
	var provider: GameplayPlacementProvider3D = GameplayPlacementProvider3D.new()
	provider.ability = ability
	provider.max_range = 10.0

	var reachable: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	reachable.append_location(SPOT, Vector3.UP)
	assert_true(
		provider.validate_authoritative(reachable, fixture.asc), "three metres away"
	)

	var unreachable: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	unreachable.append_location(FAR, Vector3.UP)
	assert_false(
		provider.validate_authoritative(unreachable, fixture.asc),
		"and five hundred is not"
	)


## A placement that is out of range aims at nothing rather than refusing.
##
## Somebody dragging a marker past the edge of their range is still aiming, and
## an aim that ended there would be one they could not drag back.
func test_a_placement_out_of_range_aims_at_nothing_rather_than_stopping() -> void:
	var provider: GameplayPlacementProvider3D = GameplayPlacementProvider3D.new()
	provider.max_range = 10.0
	provider.begin(ability)

	provider.position = FAR
	var refused: GameplayAbilityTargetData = provider.update_preview()
	assert_false(refused.has_locations(), "nothing is being aimed at")
	assert_false(provider.placeable, "and it says so, for whatever is drawing")
	assert_true(provider.is_choosing(), "but the aim is still going")

	provider.position = SPOT
	assert_true(provider.update_preview().has_locations(), "and it comes back")
#endregion
