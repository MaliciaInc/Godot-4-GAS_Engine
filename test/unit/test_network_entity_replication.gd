## How much is said about one entity, and the cues nobody else hears about.
##
## Two decisions a game makes per entity rather than per project. A boss whose
## every attribute matters and a crowd of villagers whose health bar is the
## whole of what anybody sees are two different amounts of network, and a
## runtime with one setting makes a game choose the expensive one for both. A
## cue can play here and be nobody else business - the crunch under your own
## footsteps is not worth a packet - which is a different question from whether
## it is suppressed.
##
## Their own suite rather than more of the replication one, which is about what
## a reading contains: these are about who decides how much of it there is.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

const IMPACT: StringName = &"Cue.Impact"
const OWNING_PEER: int = 2
const WATCHING_PEER: int = 3
const A_PATH: String = "res://test_only/entity_replicated_%d.tres"

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
## An effect that can be named to another machine, which means one that lives
## somewhere: a resource built in memory has nothing to call it.
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


## An effect whose persistent cue is nobody else business.
func _with_a_local_cue(tag: StringName) -> GameplayEffect:
	var effect: GameplayEffect = EffectFactory.with_persistent_cues(
		EffectFactory.infinite(_no_modifiers()), [tag]
	)
	for binding: GameplayCueBinding in effect.cues:
		binding.replication = GameplayCueBinding.Replication.LOCAL_ONLY
	return _named(effect)
#endregion


#region How much is said about one entity
## An entity says how much is replicated about it, and the runtime says what
## the rest do.
##
## A boss whose every attribute matters and a crowd of villagers whose health
## bar is the whole of what anybody sees are two different amounts of network,
## and a runtime with one setting makes a game choose the expensive one for
## everybody.
func test_an_entity_can_say_how_much_is_replicated_about_it() -> void:
	assert_eq(
		authority.registry.replication_mode_for(entity, GameplayNetReplication.Mode.MIXED),
		GameplayNetReplication.Mode.MIXED,
		"an entity that asked for nothing follows the fallback"
	)

	assert_true(
		authority.registry.set_replication_mode(entity, GameplayNetReplication.Mode.MINIMAL),
		"it can say otherwise"
	)
	assert_eq(
		authority.registry.replication_mode_for(entity, GameplayNetReplication.Mode.FULL),
		GameplayNetReplication.Mode.MINIMAL,
		"and is asked rather than the fallback"
	)

	assert_true(authority.registry.clear_replication_mode(entity), "it can stop saying it")
	assert_eq(
		authority.registry.replication_mode_for(entity, GameplayNetReplication.Mode.FULL),
		GameplayNetReplication.Mode.FULL,
		"and follows the runtime again"
	)


## Saying it about an entity nobody registered is a mistake worth learning about.
func test_a_mode_set_on_nobody_is_refused() -> void:
	var nobody: GameplayNetEntityId = GameplayNetEntityId.of(999)

	assert_false(
		authority.registry.set_replication_mode(nobody, GameplayNetReplication.Mode.FULL),
		"there is nobody to say it about"
	)
	assert_false(authority.registry.clear_replication_mode(nobody), "nor to stop saying it")


## What the entity asked for is what a reading of it uses.
func test_the_reading_uses_what_the_entity_asked_for() -> void:
	EffectFactory.apply(asc, _named(EffectFactory.infinite(_no_modifiers())))
	authority.replication_mode = GameplayNetReplication.Mode.FULL
	assert_gt(
		authority.snapshot_for(entity, WATCHING_PEER).state.effects.size(), 0,
		"the runtime's own default tells a watcher about the effects"
	)

	authority.registry.set_replication_mode(entity, GameplayNetReplication.Mode.MINIMAL)
	assert_eq(
		authority.snapshot_for(entity, WATCHING_PEER).state.effects.size(), 0,
		"and the entity's own answer overrules it"
	)
#endregion


#region Cues nobody else hears about
## A local-only cue never reaches a wire.
##
## Two different questions that used to be one: a cue can be suppressed and
## still have to be told to everybody, and a cue can play here and be nobody
## else's business.
func test_a_local_only_cue_stays_where_it_was_decided() -> void:
	EffectFactory.apply(asc, _with_a_local_cue(IMPACT))

	assert_false(
		_snapshot().cues.has(IMPACT), "it is not in what another machine is told"
	)
	assert_true(
		asc.get_active_effects().size() > 0, "while the effect that plays it is running"
	)


## A replicated one still goes out, which is the other half.
func test_a_replicated_cue_still_goes_out() -> void:
	EffectFactory.apply(
		asc,
		_named(EffectFactory.with_persistent_cues(
			EffectFactory.infinite(_no_modifiers()), [IMPACT]
		))
	)

	assert_true(_snapshot().cues.has(IMPACT), "the default is still to tell everybody")
#endregion
