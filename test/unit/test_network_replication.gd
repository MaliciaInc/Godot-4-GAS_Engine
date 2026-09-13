## Telling another machine what a character is, and what has changed since.
##
## Attributes, tags, abilities, active effects and their counts, remaining
## duration and turns, and cues. A snapshot is all of it and a delta is the
## part that moved, and they are the same shape on purpose - a late joiner is
## a peer whose whole state is news.
##
## The client does not re-simulate: attributes and tags are written onto the
## component, and effects are handed over as a reading for a game to show.
## Applying them as effects again would count everything twice.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const HEALTH: StringName = &"health"
const ATTACK: StringName = &"attack"
const BURNING: StringName = &"Status.Burning"
const IMPACT: StringName = &"Cue.Impact"
const OWNING_PEER: int = 2
const WATCHING_PEER: int = 3
const A_PATH: String = "res://test_only/replicated_%d.tres"

var made: int = 0
var authority: GameplayNetworkRuntime = null
var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var entity: GameplayNetEntityId = null


func before_each() -> void:
	var bench: NetBench = NetBench.built(self, "Replicated")
	autofree(bench.fixture.owner)
	authority = bench.runtime
	fixture = bench.fixture
	asc = bench.asc()
	entity = bench.entity


func after_each() -> void:
	authority.dispose()
	authority = null
	fixture = null
	asc = null
	entity = null


#region Getting there
## An effect nameable to another machine - a resource built in memory has
## nothing to call it.
func _named(effect: GameplayEffect) -> GameplayEffect:
	made += 1
	effect.take_over_path(A_PATH % made)
	return effect


func _snapshot(
	mode: GameplayNetReplication.Mode = GameplayNetReplication.Mode.FULL, for_owner: bool = true
) -> GameplayNetState:
	return GameplayNetReplication.snapshot_of(asc, authority.registry, mode, for_owner)


func _no_modifiers() -> Array[GameplayEffectModifier]:
	return [] as Array[GameplayEffectModifier]

#endregion




#region A snapshot is what is there
## Base values, composed values, and reference counts - both attribute
## readings, with a buff on to tell them apart (AUD-08).
func test_a_snapshot_carries_the_base_attributes_and_the_tag_counts() -> void:
	fixture.set_base(HEALTH, 70.0)
	EffectFactory.apply(
		asc,
		_named(
			EffectFactory.infinite(
				[EffectFactory.add(HEALTH, 25.0)] as Array[GameplayEffectModifier]
			)
		)
	)
	asc.add_tag(BURNING)
	asc.add_tag(BURNING)
	assert_almost_eq(asc.get_attribute_current(HEALTH), 95.0, 0.001, "the buff is really on")

	var state: GameplayNetState = _snapshot()

	assert_almost_eq(state.attributes[HEALTH], 70.0, 0.001, "the base value")
	assert_almost_eq(
		state.current_attributes[HEALTH], 95.0, 0.001,
		"and the composed one too - AUD-08, a receiver that does not re-simulate needs both"
	)
	assert_eq(state.tags[BURNING], 2, "counts, because a tag held twice is still held once over")


func test_a_snapshot_carries_what_is_granted() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, Probe.build(&"Ability.Replicated"))
	made += 1
	spec.definition.ability_scene.take_over_path(A_PATH % made)

	var state: GameplayNetState = _snapshot()

	assert_eq(state.abilities.size(), 1, "one grant, named by its definition")
	assert_ne(state.abilities[0], GameplayNetDefinitionId.NONE)


## And one granted from a scene that lives nowhere is not named at all - an
## ability packed in memory and never saved cannot be pointed at on another
## machine, so it is left out rather than sent under an id the receiver
## would resolve to whatever it happened to have.
func test_a_grant_from_a_scene_that_lives_nowhere_is_not_sent() -> void:
	AbilityFactory.give(asc, Probe.build(&"Ability.Unsaved"))

	assert_true(_snapshot().abilities.is_empty())


## Which effect, how many, how long left, and whether it is doing anything.
func test_a_snapshot_carries_each_running_effect_and_its_readings() -> void:
	var carrier: GameplayEffect = _named(
		EffectFactory.stacked(
			EffectFactory.duration(_no_modifiers(), 12.0),
			GameplayEffect.StackingType.AGGREGATE_BY_TARGET,
			3
		)
	)
	EffectFactory.apply(asc, carrier)
	EffectFactory.apply(asc, carrier)

	var state: GameplayNetState = _snapshot()

	assert_eq(state.effects.size(), 1, "one application, stacked")
	var reading: GameplayNetEffectState = state.effects[0]
	assert_eq(reading.stack_count, 2, "two of it")
	assert_almost_eq(reading.time_remaining, 12.0, 0.001, "and this long left")
	assert_false(reading.inhibited, "and it is doing something")
	assert_true(reading.is_valid(), "named on both machines")


## Turns and seconds are two clocks, and an effect uses one of them.
func test_a_turn_based_effect_carries_its_turns_and_not_a_clock() -> void:
	EffectFactory.apply(asc, _named(EffectFactory.turn_based(_no_modifiers(), 4)))

	var reading: GameplayNetEffectState = _snapshot().effects[0]

	assert_eq(reading.remaining_turns, 4, "four turns")
	assert_almost_eq(reading.time_remaining, 0.0, 0.001, "and no seconds to count down")


func test_a_snapshot_carries_the_persistent_cues_that_are_playing() -> void:
	EffectFactory.apply(
		asc,
		_named(EffectFactory.with_persistent_cues(EffectFactory.infinite(_no_modifiers()), [IMPACT]))
	)

	assert_true(_snapshot().cues.has(IMPACT))
#endregion


#region How much each peer is told
##     [the mode, whether this is the owner, whether it hears about effects]
func _modes() -> Array:
	return [
		["full, to the owner", GameplayNetReplication.Mode.FULL, true, true],
		["full, to anybody else", GameplayNetReplication.Mode.FULL, false, true],
		["mixed, to the owner", GameplayNetReplication.Mode.MIXED, true, true],
		["mixed, to anybody else", GameplayNetReplication.Mode.MIXED, false, false],
		["minimal, even to the owner", GameplayNetReplication.Mode.MINIMAL, true, false],
	]


## The effects are the expensive half and the private half at once; the tags
## and cues travel in every mode, because they are what anybody watching can see.
func test_the_mode_decides_who_hears_about_the_effects() -> void:
	var rows: Array = _modes()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var mode: GameplayNetReplication.Mode = row[1]
		var for_owner: bool = row[2]
		var hears: bool = row[3]

		before_each()
		asc.add_tag(BURNING)
		EffectFactory.apply(
			asc,
			_named(
				EffectFactory.with_persistent_cues(
					EffectFactory.infinite(_no_modifiers()), [IMPACT]
				)
			)
		)

		var state: GameplayNetState = _snapshot(mode, for_owner)

		assert_eq(state.effects.is_empty(), not hears, described)
		assert_eq(state.tags[BURNING], 1, "%s: the tags travel regardless" % described)
		assert_true(state.cues.has(IMPACT), "%s: and so do the cues" % described)
		checked += 1
	assert_eq(checked, rows.size(), "every mode was asked")
#endregion


#region A delta is what changed
func test_a_delta_carries_only_what_moved() -> void:
	fixture.set_base(HEALTH, 100.0)
	fixture.set_base(ATTACK, 5.0)
	var before: GameplayNetState = _snapshot()
	fixture.set_base(HEALTH, 60.0)

	var change: GameplayNetState = GameplayNetReplication.delta_between(before, _snapshot())

	assert_true(change.is_delta(), "it says which it is")
	assert_true(change.attributes.has(HEALTH), "health moved")
	assert_false(change.attributes.has(ATTACK), "and attack did not")


## A buff that never moved the base is still news (AUD-08): applying an effect
## leaves base where it was, and current is the only field that says anything happened.
func test_a_delta_notices_a_buff_that_never_moved_the_base() -> void:
	fixture.set_base(HEALTH, 70.0)
	var before: GameplayNetState = _snapshot()
	EffectFactory.apply(
		asc, _named(EffectFactory.infinite([EffectFactory.add(HEALTH, 25.0)] as Array[GameplayEffectModifier]))
	)

	var change: GameplayNetState = GameplayNetReplication.delta_between(before, _snapshot())

	assert_false(change.attributes.has(HEALTH), "the base never moved")
	assert_almost_eq(change.current_attributes[HEALTH], 95.0, 0.001, "but the composed value did")


## An absence cannot be expressed by a value: a tag that is gone and a tag
## nobody mentioned look identical in a dictionary.
func test_a_delta_says_what_went_away_as_well() -> void:
	asc.add_tag(BURNING)
	var before: GameplayNetState = _snapshot()
	asc.remove_tag(BURNING)

	var change: GameplayNetState = GameplayNetReplication.delta_between(before, _snapshot())

	assert_true(change.removed_tags.has(BURNING))
	assert_false(change.tags.has(BURNING), "gone is not a count")


func test_a_delta_notices_an_effect_gaining_a_stack_and_an_effect_ending() -> void:
	var carrier: GameplayEffect = _named(
		EffectFactory.stacked(
			EffectFactory.infinite(_no_modifiers()),
			GameplayEffect.StackingType.AGGREGATE_BY_TARGET,
			3
		)
	)
	var active: ActiveGameplayEffect = EffectFactory.apply(asc, carrier)
	var before: GameplayNetState = _snapshot()
	EffectFactory.apply(asc, carrier)

	var stacked: GameplayNetState = GameplayNetReplication.delta_between(before, _snapshot())
	assert_eq(stacked.effects.size(), 1, "one more of it is news")
	assert_eq(stacked.effects[0].stack_count, 2)

	var during: GameplayNetState = _snapshot()
	asc.effects.remove(active)
	var ended: GameplayNetState = GameplayNetReplication.delta_between(during, _snapshot())
	assert_eq(ended.ended_effects.size(), 1, "and so is its ending")
	assert_true(ended.effects.is_empty(), "which is not the same as a change to it")


func test_a_delta_with_nothing_in_it_says_so() -> void:
	var before: GameplayNetState = _snapshot()

	assert_true(
		GameplayNetReplication.delta_between(before, _snapshot()).is_empty(),
		"nothing happened, and a message for it would be bandwidth spent saying so"
	)
#endregion


#region Writing one on
func test_applying_a_snapshot_writes_the_attributes_and_the_tags() -> void:
	fixture.set_base(HEALTH, 100.0)
	asc.add_tag(BURNING)
	var state: GameplayNetState = _snapshot()

	var other: ASCFixture = Fixture.create("Listener")
	add_child_autofree(other.owner)
	assert_true(GameplayNetReplication.apply(state, other.asc))

	assert_almost_eq(other.asc.get_attribute_base(HEALTH), 100.0, 0.001)


## The composed value is written straight onto the receiver rather than
## derived (AUD-08), proved with a buff the receiver was never given.
func test_applying_a_reading_writes_the_current_value_without_deriving_it() -> void:
	fixture.set_base(HEALTH, 70.0)
	EffectFactory.apply(
		asc, _named(EffectFactory.infinite([EffectFactory.add(HEALTH, 25.0)] as Array[GameplayEffectModifier]))
	)
	var state: GameplayNetState = _snapshot(GameplayNetReplication.Mode.MIXED, false)
	assert_true(state.effects.is_empty(), "a non-owner under MIXED is told nothing of the effect itself")

	var other: ASCFixture = Fixture.create("Onlooker")
	add_child_autofree(other.owner)
	GameplayNetReplication.apply(state, other.asc)

	assert_almost_eq(
		other.asc.get_attribute_current(HEALTH), 95.0, 0.001,
		"the composed answer arrived on its own, with no effect to have composed it from"
	)


## A snapshot is the whole truth, so a tag it does not mention is one that is
## not there. A delta could never say that, which is why the two are told apart.
func test_a_snapshot_takes_away_a_tag_it_does_not_mention_and_a_delta_does_not() -> void:
	var empty: GameplayNetState = _snapshot()
	var change: GameplayNetState = GameplayNetState.delta()

	var listener: ASCFixture = Fixture.create("Listener")
	add_child_autofree(listener.owner)
	listener.asc.add_tag(BURNING)
	GameplayNetReplication.apply(change, listener.asc)
	assert_eq(listener.asc.tags.count_exact(BURNING), 1, "a delta says nothing about it")

	GameplayNetReplication.apply(empty, listener.asc)
	assert_eq(listener.asc.tags.count_exact(BURNING), 0, "a snapshot says it is not there")


## Values and not increments, which is what makes a repeat harmless.
func test_applying_the_same_reading_twice_lands_in_the_same_place() -> void:
	asc.add_tag(BURNING)
	asc.add_tag(BURNING)
	var state: GameplayNetState = _snapshot()

	var listener: ASCFixture = Fixture.create("Listener")
	add_child_autofree(listener.owner)
	GameplayNetReplication.apply(state, listener.asc)
	GameplayNetReplication.apply(state, listener.asc)

	assert_eq(listener.asc.tags.count_exact(BURNING), 2, "twice held, not four times")
#endregion


#region Late join, and readings that arrive out of order
func _listening() -> GameplayNetworkRuntime:
	var client: GameplayNetworkRuntime = GameplayNetworkRuntime.new()
	client.role = GameplayNetAuthority.Role.CLIENT
	client.peer = WATCHING_PEER
	var listener: ASCFixture = Fixture.create("LateJoiner")
	add_child_autofree(listener.owner)
	client.attach(listener.asc, entity, OWNING_PEER)
	return client


## A delta is what changed. A peer with nothing for it to have changed from
## would apply half a character and believe it had all of one.
func test_a_delta_before_any_snapshot_is_refused() -> void:
	var client: GameplayNetworkRuntime = _listening()
	var refused: Array[StringName] = []
	client.message_refused.connect(
		func(_message: GameplayNetMessage, reason: StringName) -> void: refused.append(reason)
	)
	fixture.set_base(HEALTH, 100.0)
	authority.snapshot_for(entity, WATCHING_PEER)
	fixture.set_base(HEALTH, 40.0)
	var change: GameplayNetMessage = authority.delta_for(entity, WATCHING_PEER)

	assert_not_null(change, "the authority had something to say")
	assert_false(client.receive(change), "and the late joiner cannot use it yet")
	assert_true(refused.has(GameplayNetworkRuntime.REASON_NOTHING_TO_UPDATE))
	client.dispose()


## Two readings, and which one the character ends up at.
##
## The late join and the reordered packet are one question asked twice. A peer
## applies what it is told, and the thing it must never do is end up holding an
## older reading than the newest one it has already seen - which would put a
## character back the way it was and leave it there until that same attribute
## happens to change again.
##
##     [what happens, whether the second is a delta, arriving backwards, the end]
func _readings() -> Array:
	return [
		["a snapshot and then a delta", true, false, 40.0],
		["two snapshots, the older arriving last", false, true, 40.0],
	]


func test_a_peer_ends_at_the_newest_reading_it_was_sent() -> void:
	var rows: Array = _readings()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var second_is_a_delta: bool = row[1]
		var backwards: bool = row[2]
		var ends_at: float = row[3]

		before_each()
		var client: GameplayNetworkRuntime = _listening()
		fixture.set_base(HEALTH, 100.0)
		var first: GameplayNetMessage = authority.snapshot_for(entity, WATCHING_PEER)
		fixture.set_base(HEALTH, 40.0)
		var second: GameplayNetMessage = (
			authority.delta_for(entity, WATCHING_PEER) if second_is_a_delta
			else authority.snapshot_for(entity, WATCHING_PEER)
		)
		assert_not_null(second, "%s: the authority had something to say" % described)

		if backwards:
			client.receive(second)
			client.receive(first)
		else:
			client.receive(first)
			client.receive(second)

		assert_almost_eq(
			client.registry.asc_for(entity).get_attribute_base(HEALTH), ends_at, 0.001, described
		)
		client.dispose()
		checked += 1
	assert_eq(checked, rows.size(), "both orders were sent")
#endregion


#region Respawn
## The component stays where the grants are; the avatar is what effects and
## cues happen to. Swapping it is a respawn, and a respawn that lost the grants
## would be a character that came back without its abilities.
func test_swapping_the_avatar_keeps_everything_the_component_owns() -> void:
	fixture.set_base(HEALTH, 55.0)
	asc.add_tag(BURNING)
	AbilityFactory.give(asc, Probe.build(&"Ability.Survives"))
	var before: GameplayNetState = _snapshot()

	var reborn: Node = Node.new()
	add_child_autofree(reborn)
	asc.init_ability_actor_info(fixture.owner, reborn)

	var after: GameplayNetState = _snapshot()
	assert_same(asc.actor_info.avatar, reborn, "the body is new")
	assert_true(
		GameplayNetReplication.delta_between(before, after).is_empty(),
		"and nothing the component owns moved with it"
	)
#endregion
