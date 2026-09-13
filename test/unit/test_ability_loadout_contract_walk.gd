## One character, one loadout, and every ability contract used the way a game
## would use it.
##
## Each piece has its own tests. This exists because pieces that pass separately
## can still be wrong together: a trigger that cancels an ability while a task is
## waiting on a confirm, a custom cost taken during a commit that a loadout is
## about to retire. The walk is one scenario end to end, and it finishes by
## proving the component is exactly what it was before any of it happened.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const BURNING: StringName = &"Status.Burning"
const HIT: StringName = &"Event.Hit"
const CONDITIONAL: StringName = &"Ability.Conditional"
const LISTENING: StringName = &"Ability.Listening"
const PRICED: StringName = &"Ability.Priced"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Walker")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	RecordingCustomCost.ledger = []


func after_each() -> void:
	fixture = null
	asc = null


#region Building the loadout
func _packed(ability: GameplayAbility) -> PackedScene:
	var scene: PackedScene = PackedScene.new()
	scene.pack(ability)
	ability.free()
	return scene


func _entry(scene: PackedScene, input_id: int = -1) -> GameplayAbilitySetEntry:
	var entry: GameplayAbilitySetEntry = GameplayAbilitySetEntry.new()
	entry.ability_scene = scene
	entry.input_id = input_id
	return entry


## Runs while its condition holds: the level trigger of F6.1.1, on a channelling
## ability so the walk can watch it stop when the condition goes.
func _conditional() -> PackedScene:
	var channelling: ChannelingAbility = ChannelingAbility.new()
	channelling.ability_tags = [CONDITIONAL] as Array[StringName]
	channelling.activation_policy = GameplayAbility.ActivationPolicy.ON_GAMEPLAY_EVENT
	var trigger: GameplayAbilityEventTrigger = GameplayAbilityEventTrigger.for_tag(BURNING)
	trigger.source = GameplayAbilityEventTrigger.Source.OWNED_TAG_PRESENT
	channelling.gameplay_event_triggers = [trigger]
	return _packed(channelling)


func _listening() -> PackedScene:
	return _packed(Probe.build(LISTENING))


## Priced with a cost this engine cannot price, which is F6.1.6's whole point.
func _priced() -> PackedScene:
	var probe: ProbeAbility = Probe.build(PRICED)
	probe.commits = true
	var cost: RecordingCustomCost = RecordingCustomCost.new()
	cost.label = &"ammo"
	probe.custom_costs = [cost] as Array[GameplayAbilityCustomCost]
	return _packed(probe)


func _kit() -> GameplayAbilitySet:
	var kit: GameplayAbilitySet = GameplayAbilitySet.new()
	kit.abilities = [
		_entry(_conditional()), _entry(_listening()), _entry(_priced(), 1)
	] as Array[GameplayAbilitySetEntry]
	kit.effects = [
		Factory.granting(
			Factory.infinite([] as Array[GameplayEffectModifier]),
			[&"Kit.Worn"] as Array[StringName]
		)
	] as Array[GameplayEffect]
	kit.attribute_sets = [VehicleAttributeSet.new()] as Array[AttributeSet]
	return kit


## The running instance of the ability carrying a tag, or null.
func _named(tag: StringName) -> GameplayAbility:
	for spec: GameplayAbilitySpec in asc.get_ability_specs():
		if spec.definition.ability_tags.has(tag):
			return spec.per_actor_instance
	return null
#endregion


func test_the_whole_ability_contract_walks_and_leaves_nothing_behind() -> void:
	var before: Dictionary = fixture.snapshot()

	# 1. The loadout goes on as one thing.
	var receipt: GameplayAbilitySetHandles = _kit().grant(asc)
	assert_eq(receipt.undo_steps.size(), 5, "three abilities, one effect, one set")
	assert_true(asc.has_tag(&"Kit.Worn"), "the kit's effect is on")

	# 2. A level trigger starts its ability the moment the condition holds.
	asc.add_tag(BURNING)
	var conditional: GameplayAbility = _named(CONDITIONAL)
	assert_true(conditional.is_active, "burning, so it is running")

	# 3. And stops when the condition goes.
	asc.remove_tag(BURNING)
	assert_false(conditional.is_active, "no longer burning, no longer running")

	# 4. A continuous listener hears every event, with the payload filled in.
	var listening: GameplayAbility = _named(LISTENING)
	var heard: Array[GameplayEventData] = []
	var listener: AbilityTaskWaitGameplayEvent = listening.wait_gameplay_events(HIT)
	listener.event_received.connect(
		func(event: GameplayEventData) -> void: heard.append(event)
	)
	asc.add_tag(&"Caster.Undead")
	asc.send_gameplay_event(_hit())
	asc.send_gameplay_event(_hit())

	assert_eq(heard.size(), 2, "both of them, because it was told to stay")
	assert_true(
		heard[0].instigator_tags.has(&"Caster.Undead"),
		"and each carried what the instigator was at the time"
	)

	# 5. A custom cost is taken as part of one atomic commit.
	var priced: GameplayAbility = _named(PRICED)
	assert_true(priced.commit_ability().is_ok(), "it paid")
	assert_true(RecordingCustomCost.ledger.has(&"commit:ammo"), "the custom cost was taken")

	# 6. A generic confirm resolves a waiting task without naming a key.
	var waiting: AbilityTaskWaitConfirmCancel = AbilityTaskWaitConfirmCancel.create(listening)
	listening._own(waiting)
	asc.input_confirm()
	assert_true(waiting.is_finished(), "the task heard the confirm")
	assert_eq(
		waiting.decision, AbilityTaskWaitConfirmCancel.Decision.CONFIRMED, "and what it was"
	)

	# 7. And the whole thing comes off, leaving the component as it was found.
	listener.cancel(GameplayAbilityTask.CancelReason.ABILITY_ABORTED)
	asc.remove_tag(&"Caster.Undead")
	assert_true(receipt.take_back(), "the loadout came off")

	assert_eq(fixture.snapshot(), before, "and the component is what it was")


func _hit() -> GameplayEventData:
	var event: GameplayEventData = GameplayEventData.new()
	event.event_tag = HIT
	event.instigator = fixture.owner
	event.target = fixture.owner
	return event
