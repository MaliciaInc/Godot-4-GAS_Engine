## The workloads, at the scales the phase names.
##
## Seven of them, because they are the seven places an ability system is asked
## to do the same thing many times: standing characters up, running effects on
## one of them, asking about tags, recomposing an attribute, re-deciding whether
## a passive still holds, filtering candidates, and packing state for the wire.
##
## Each is a Callable the probe times, and a matching one that frees what it
## made. Freeing is not timed - what it costs to make a thousand components is
## not what it costs to take them down again, and reporting the two as one
## number would make both unreadable.
##
## Nothing is indexed or batched here. The phase is explicit that optimisation
## comes after measurement, and this is the measurement.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayPerfScenarios extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

## The three the phase names.
const SCALES: Array[int] = [10, 100, 1000]

const ATTACK: StringName = &"attack"
const HEALTH: StringName = &"health"
const FAMILY: StringName = &"State.Debuff"
const LEAF: StringName = &"State.Debuff.Stunned"
const AT_PATH: String = "res://test_only/perf_%d.tres"

## What the workloads made, so the caller can take it down again.
var built: Array[Node] = []

var _host: Node = null
var _made: int = 0


static func on(host: Node) -> GameplayPerfScenarios:
	var scenarios: GameplayPerfScenarios = GameplayPerfScenarios.new()
	scenarios._host = host
	return scenarios


## Free everything the last run made.
func clean() -> void:
	for node: Node in built:
		if is_instance_valid(node):
			node.free()
	built.clear()


#region The workloads
## Standing characters up: the cost of an entity existing at all.
func components(count: int) -> Callable:
	return func() -> void:
		for _index: int in count:
			var fixture: ASCFixture = Fixture.create("Perf")
			_host.add_child(fixture.owner)
			built.append(fixture.owner)


## Running effects on one character, which is where aggregation gets expensive.
func effects(count: int) -> Callable:
	var fixture: ASCFixture = _one()
	return func() -> void:
		for _index: int in count:
			EffectFactory.apply(fixture.asc, _named(EffectFactory.infinite(
				[EffectFactory.add(ATTACK, 1.0)] as Array[GameplayEffectModifier]
			)))


## Asking about tags, hierarchically, which every gate in the engine does.
func tag_lookups(count: int) -> Callable:
	var fixture: ASCFixture = _one()
	fixture.asc.add_tag(LEAF)
	return func() -> void:
		for _index: int in count:
			fixture.asc.has_tag(FAMILY)


## Recomposing an attribute from everything contributing to it.
func recomposition(count: int) -> Callable:
	var fixture: ASCFixture = _one()
	for _index: int in 8:
		EffectFactory.apply(fixture.asc, _named(EffectFactory.infinite(
			[EffectFactory.add(ATTACK, 1.0)] as Array[GameplayEffectModifier]
		)))
	return func() -> void:
		for _index: int in count:
			fixture.asc.attributes.recompose_all()


## Re-deciding whether every passive still holds.
func passive_reevaluation(count: int) -> Callable:
	var fixture: ASCFixture = _one()
	return func() -> void:
		for _index: int in count:
			fixture.asc.ability_runtime.reevaluate_passives()


## Filtering candidates, which is the half of targeting that is not physics.
func targeting_queries(count: int) -> Callable:
	var fixture: ASCFixture = _one()
	var filter: GameplayTargetFilter = GameplayTargetFilter.new()
	var candidates: Array[Node] = []
	for _index: int in 16:
		var other: ASCFixture = _one()
		candidates.append(other.owner)
	return func() -> void:
		for _index: int in count:
			for candidate: Node in candidates:
				filter.accepts(fixture.asc, candidate)


## Packing a character's state for the wire, and working out what changed.
func network_serialization(count: int) -> Callable:
	var fixture: ASCFixture = _one()
	fixture.set_base(HEALTH, 100.0)
	var registry: GameplayNetRegistry = GameplayNetRegistry.new()
	return func() -> void:
		for _index: int in count:
			var before: GameplayNetState = GameplayNetReplication.snapshot_of(
				fixture.asc, registry
			)
			GameplayNetReplication.delta_between(
				before, GameplayNetReplication.snapshot_of(fixture.asc, registry)
			)
#endregion


#region Getting there
func _one() -> ASCFixture:
	var fixture: ASCFixture = Fixture.create("Perf")
	_host.add_child(fixture.owner)
	built.append(fixture.owner)
	fixture.asc.set_process(false)
	return fixture


func _named(effect: GameplayEffect) -> GameplayEffect:
	_made += 1
	effect.take_over_path(AT_PATH % _made)
	return effect
#endregion
