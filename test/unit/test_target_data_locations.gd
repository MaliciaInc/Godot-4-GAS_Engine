## An aim that is a place rather than a thing, and what crosses a wire of it.
##
## Split from test_target_data.gd, which is about hits with a collider on them.
## What is being proved here is the difference: a ground-targeted spell lands
## somewhere whether or not anybody is standing on the spot, and the engine must
## not invent a Node for the spot or go looking for somebody nearby.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const TOLERANCE: float = 0.0001
const SPOT_2D: Vector2 = Vector2(7.0, -2.0)
const UP_2D: Vector2 = Vector2(0.0, 1.0)
const SPOT_3D: Vector3 = Vector3(5.0, 0.0, -9.0)
const UP_3D: Vector3 = Vector3(0.0, 1.0, 0.0)

## Half a centimetre, in metres: the most a place can move by being rounded to
## the centimetre it crosses at - and a little float32 room on top.
const CENTIMETRE_ROUNDING: float = 0.0051

var data: GameplayAbilityTargetData = null


func before_each() -> void:
	data = GameplayAbilityTargetData.new()


func after_each() -> void:
	data = null


#region A place is not a thing
## A location is recorded, and nothing is invented to stand at it.
##
##     [what it is called, the position, the normal]
func _location_cases() -> Array:
	return [["in two dimensions", SPOT_2D, UP_2D], ["in three", SPOT_3D, UP_3D]]


func test_a_location_is_recorded_without_inventing_anything_to_stand_there(
	case: Array = use_parameters(_location_cases())
) -> void:
	var described: String = case[0]
	var position: Variant = case[1]
	var normal: Variant = case[2]

	assert_true(data.append_location(position, normal), "%s: it was accepted" % described)

	assert_true(data.has_locations(), "%s: and it is a place" % described)
	assert_eq(
		data.get_target_nodes().size(), 0, "%s: with nothing standing at it" % described
	)
	assert_false(data.has_targets(), "%s: so there is nobody to hit" % described)
	var hit: GameplayTargetHit = data.get_all_hits()[0]
	assert_null(hit.collider, "%s: the hit knows there was nothing there" % described)
	assert_true(hit.has_position, "%s: and knows where it happened" % described)


## A position and a normal that disagree about how many dimensions they are in
## are refused, the same way a physics hit is - a half-recorded hit reads as
## valid to everything downstream.
func test_a_mixed_dimension_location_is_refused() -> void:
	assert_false(data.append_location(SPOT_2D, UP_3D), "two and three do not mix")
	assert_eq(data.get_all_hits().size(), 0, "and nothing was recorded")


## A hit with a collider is not a location, however well it knows where it is.
##
## The distinction is what `has_locations` is for: an ability that reached no
## actors wants to know whether it was aimed at a place or at nobody at all.
func test_a_hit_on_something_is_not_a_location() -> void:
	var body: Node3D = Node3D.new()
	add_child_autofree(body)

	data.append_node(body)

	assert_false(data.has_locations(), "it was aimed at something")
	assert_eq(data.get_target_nodes().size(), 1, "and that something is a target")
#endregion


#region Applying to a place
## An effect aimed at a place reaches nobody, and says which kind of nobody.
##
## No implicit overlap: an area effect nobody authored, with a radius nobody
## chose, is worse than an effect that did nothing.
func test_applying_to_a_location_reaches_nobody_and_says_so() -> void:
	var fixture: ASCFixture = Fixture.create("Caster")
	add_child_autofree(fixture.owner)
	var ability: GameplayAbility = TestAbilityFactory.give(
		fixture.asc, Probe.build(&"Ability.Ground")
	).per_actor_instance
	data.append_location(SPOT_3D, UP_3D)

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		Factory.instant([Factory.add(&"health", -10.0)]), data
	)

	assert_eq(result.attempted_targets, 0, "nobody was attempted")
	assert_eq(result.applied_count(), 0, "and nothing was applied")
	assert_eq(
		result.refusal,
		GameplayTargetApplicationResult.Refusal.NO_ACTOR_TARGETS,
		"and the reason is that the aim held no actors"
	)
	assert_almost_eq(
		fixture.current_of(&"health"), 100.0, TOLERANCE, "the caster is untouched"
	)
#endregion


#region Across a wire
## An aim after a real crossing, as bytes, in the message an aim travels in.
##
## A round trip that handed the shape straight back would prove the translator
## and nothing about the crossing - and the crossing is where a text wire once
## turned every position into the string `(3, 0, 0)`, so that no aimed ability
## worked between two processes.
func _crossed(aim: GameplayNetAim, described: String) -> GameplayNetAim:
	var carrying: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.TARGET_DATA, GameplayNetEntityId.of(3)
	)
	carrying.activation = GameplayNetActivationId.of(carrying.entity, 1)
	carrying.prediction_key = GameplayPredictionKey.of(2, 1)
	carrying.aim = aim
	var arrived: GameplayNetMessage = GameplayNetCodec.decode(GameplayNetCodec.encode(carrying))
	assert_not_null(arrived, "%s: it crossed as bytes" % described)
	return arrived.aim if arrived != null else GameplayNetAim.new()


## Both dimensions round-trip, and what was hit crosses as an identity.
##
##     [what it is called, the position, the normal]
func _round_trip_cases() -> Array:
	return [["in two dimensions", SPOT_2D, UP_2D], ["in three", SPOT_3D, UP_3D]]


func test_an_aim_round_trips_as_identities_and_numbers(
	case: Array = use_parameters(_round_trip_cases())
) -> void:
	var described: String = case[0]
	var position: Variant = case[1]
	var normal: Variant = case[2]

	var struck: ASCFixture = Fixture.create("Struck")
	add_child_autofree(struck.owner)
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	var named: GameplayNetEntityId = GameplayNetEntityId.of(11)
	registry.register_entity(named, struck.asc)

	data.append_node(struck.owner)
	data.append_location(position, normal)

	var crossed: GameplayNetAim = _crossed(
		GameplayTargetDataTranslator.to_aim(data, registry), described
	)
	assert_eq(crossed.hits.size(), 2, "%s: both hits crossed" % described)
	if crossed.hits.size() == 2:
		assert_eq(
			crossed.hits[0].entity, named.value, "%s: what was hit crossed as its identity" % described
		)

	var back: GameplayAbilityTargetData = GameplayTargetDataTranslator.from_aim(crossed, registry)
	assert_eq(
		back.get_target_nodes(),
		[struck.owner] as Array[Node],
		"%s: what was hit came back as itself" % described
	)
	assert_true(back.has_locations(), "%s: and the place came back a place" % described)
	var place: GameplayTargetHit = back.get_all_hits()[1]
	if position is Vector2:
		var flat: Vector2 = position
		var facing: Vector2 = normal
		assert_eq(place.position_2d, flat, "%s: at the same spot" % described)
		assert_eq(place.normal_2d, facing, "%s: facing the same way" % described)
	else:
		var spatial: Vector3 = position
		var up: Vector3 = normal
		assert_eq(place.position_3d, spatial, "%s: at the same spot" % described)
		assert_eq(place.normal_3d, up, "%s: facing the same way" % described)


## A place crosses to the centimetre.
##
## The precision the reference keeps for a hit's location, said in this
## engine's unit: a metre here where the reference counts centimetres. A spot
## with more digits than that comes back within half of one, never further.
func test_a_place_crosses_to_the_centimetre() -> void:
	var spot: Vector3 = Vector3(1.23456, -7.891, 1000.004)
	data.append_location(spot, UP_3D)

	var back: GameplayAbilityTargetData = GameplayTargetDataTranslator.from_aim(
		_crossed(GameplayTargetDataTranslator.to_aim(data), "a spot with digits to spare"), null
	)
	var place: Vector3 = back.get_all_hits()[0].position_3d
	assert_almost_eq(place.x, spot.x, CENTIMETRE_ROUNDING, "across")
	assert_almost_eq(place.y, spot.y, CENTIMETRE_ROUNDING, "up")
	assert_almost_eq(place.z, spot.z, CENTIMETRE_ROUNDING, "and along, a kilometre out")


## A hit on somebody this machine has never registered comes back as nothing
## rather than as a stranger.
##
## The alternative is worse than losing the hit: a receiver that resolved an
## unknown identity to whatever was in that slot would be acting on the wrong
## character.
func test_a_hit_on_an_unknown_entity_does_not_come_back_as_somebody_else() -> void:
	var struck: ASCFixture = Fixture.create("Elsewhere")
	add_child_autofree(struck.owner)
	var sender: GameplayNetRegistry = GameplayNetRegistry.new()
	sender.register_entity(GameplayNetEntityId.of(11), struck.asc)
	data.append_node(struck.owner)

	var back: GameplayAbilityTargetData = GameplayTargetDataTranslator.from_aim(
		_crossed(GameplayTargetDataTranslator.to_aim(data, sender), "a stranger"),
		GameplayNetRegistry.new()
	)

	assert_eq(back.get_target_nodes().size(), 0, "nobody came back")
	assert_false(back.has_locations(), "and no place was invented for them either")


## A malformed aim is refused rather than repaired.
##
## A hit that says it names somebody and then names nobody is not something a
## writer produces, and an aim past the reference's ceiling of hits never
## becomes bytes at all.
func test_a_malformed_aim_is_refused_rather_than_repaired() -> void:
	var body: GameplayNetBitWriter = GameplayNetBitWriter.new()
	body.write_bits(GameplayNetMessage.Kind.TARGET_DATA, GameplayNetCodec.KIND_BITS)
	body.write_signed(3)
	body.write_bits(
		(1 << GameplayNetCodec.Carries.ACTIVATION)
		| (1 << GameplayNetCodec.Carries.PREDICTION)
		| (1 << GameplayNetCodec.Carries.BODY),
		GameplayNetCodec.CARRIES_BITS
	)
	body.write_signed(1)
	body.write_signed(2)
	body.write_signed(1)
	body.write_packed(1)
	body.write_bool(false)
	body.write_bool(true)
	body.write_bool(false)
	body.write_signed(GameplayNetEntityId.NONE)
	var packet: PackedByteArray = PackedByteArray([GameplayNetCodec.SCHEMA_VERSION, 0])
	packet.append_array(body.finish())

	assert_null(GameplayNetCodec.decode(packet), "a hit naming nobody by name")
	assert_eq(GameplayNetCodec.last_refusal, GameplayNetCodec.REASON_MALFORMED)

	var crowded: GameplayNetAim = GameplayNetAim.new()
	for _index: int in GameplayNetAim.MOST_HITS + 1:
		crowded.hits.append(GameplayNetAim.Hit.new())
	var carrying: GameplayNetMessage = GameplayNetMessage.of(
		GameplayNetMessage.Kind.TARGET_DATA, GameplayNetEntityId.of(3)
	)
	carrying.activation = GameplayNetActivationId.of(carrying.entity, 1)
	carrying.prediction_key = GameplayPredictionKey.of(2, 1)
	carrying.aim = crowded
	assert_true(
		GameplayNetCodec.encode(carrying).is_empty(),
		"and one hit past the ceiling never becomes bytes"
	)
#endregion
