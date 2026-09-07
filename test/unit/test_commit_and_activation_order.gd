## What a commit may charge, and the order in which an activation is announced.
##
## Three bugs that look unrelated and share a shape: something was decided
## earlier than the moment it was true.
##
## Affordability was decided by comparing what a cost asked to write against
## what the attribute set let through. On a set that floors at zero those two
## disagree when you cannot pay, so it worked - by accident, and only there. On
## a set that lets values go negative they agree at -10 as readily as at 10, so
## the cost read as affordable and the player was charged into debt. What can be
## paid is a question about the amount, not about the clamp.
##
## Cooldown was checked when the activation started, and paid at commit. Two
## executions that both started before either committed each looked at a world
## with no cooldown in it, and both paid.
##
## And an activation announced itself after its body had already run, so a
## listener of `ability_activated` was hearing about something that had already
## finished - and could cancel or remove an ability whose body then ran anyway.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Unclamped = preload("res://test/fixtures/unclamped_attribute_set.gd")

const MANA: StringName = &"mana"
const PROBE_TAG: StringName = &"Ability.Probe"
const COOLDOWN_TAG: StringName = &"Cooldown.Probe"
const COOLDOWN_SECONDS: float = 5.0

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Caster", Unclamped)
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _cost(amount: float) -> GameplayAbilityCost:
	var made: GameplayAbilityCost = GameplayAbilityCost.new()
	made.mode = GameplayAbilityCost.Mode.ABSOLUTE
	made.target_attribute = MANA
	made.amount = GameplayScalableFloat.new()
	made.amount.value = amount
	return made


func _cooldown() -> GameplayEffect:
	var no_modifiers: Array[GameplayEffectModifier] = []
	return Factory.granting(
		Factory.duration(no_modifiers, COOLDOWN_SECONDS), [COOLDOWN_TAG]
	)


## A granted probe, configured before the grant because that is what a grant
## snapshots.
func _granted(configure: Callable = Callable()) -> ProbeAbility:
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	if configure.is_valid():
		configure.call(probe)
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	return spec.per_actor_instance as ProbeAbility


func _mana() -> float:
	return asc.get_attribute_base(MANA)
#endregion


#region What can be paid
## What a cost charges, and what it must refuse, on a set with no floor.
##
## B07. The middle row is the bug: twenty mana against ten used to go through,
## because -10 was written exactly as asked and the old check only compared the
## write against itself. The rows either side of it are what keeps the fix
## honest - refusing everything would also make that row pass.
##
##     [what it is, mana at hand, cost, expected status, mana afterwards]
##
## Built here rather than as a `const`: an enum member is not a constant
## expression, and spelling the statuses as bare numbers would make the table
## unreadable and the first renumbering silent.
func _charges() -> Array:
	return [
		["exactly what is there", 20.0, 20.0, AbilityCommitResult.Status.SUCCESS, 0.0],
		[
			"more than is there", 10.0, 20.0,
			AbilityCommitResult.Status.INSUFFICIENT_RESOURCES, 10.0,
		],
		["less than is there", 50.0, 20.0, AbilityCommitResult.Status.SUCCESS, 30.0],
	]


func test_a_cost_is_refused_by_the_amount_and_not_by_the_clamp() -> void:
	var charges: Array = _charges()
	var checked: int = 0
	for row: Array in charges:
		var described: String = row[0]
		var at_hand: float = row[1]
		var price: float = row[2]
		var expected: AbilityCommitResult.Status = row[3]
		var left: float = row[4]

		before_each()
		asc.set_attribute_base(MANA, at_hand)
		var ability: ProbeAbility = _granted(
			func _priced(probe: ProbeAbility) -> void:
				probe.costs = [_cost(price)] as Array[GameplayAbilityCost]
		)
		asc.ability_runtime.try_activate(ability.current_spec.handle)

		assert_eq(ability.commit_ability().status, expected, "%s: the answer" % described)
		assert_almost_eq(_mana(), left, 0.0001, "%s: and what is left" % described)
		checked += 1
	assert_eq(checked, charges.size(), "every price was asked")


## Two costs against one attribute are added up before the question is asked.
##
## Fifteen and ten against twenty is affordable one at a time and not at all
## together, so a check that priced them separately would charge into debt on a
## set with no floor - the same failure by a different route.
func test_two_costs_on_one_attribute_are_added_before_deciding() -> void:
	asc.set_attribute_base(MANA, 20.0)
	var ability: ProbeAbility = _granted(
		func _priced(probe: ProbeAbility) -> void:
			probe.costs = [_cost(15.0), _cost(10.0)] as Array[GameplayAbilityCost]
	)
	asc.ability_runtime.try_activate(ability.current_spec.handle)

	var result: AbilityCommitResult = ability.commit_ability()

	assert_eq(
		result.status,
		AbilityCommitResult.Status.INSUFFICIENT_RESOURCES,
		"twenty-five against twenty is not affordable"
	)
	assert_almost_eq(_mana(), 20.0, 0.0001, "and nothing was taken")
#endregion


#region Who pays the cooldown
## Two executions that both started before either committed: only one pays.
##
## B08. Each of them checked the cooldown when it activated, and at that moment
## there was none - so both got through, and the ability went off twice on one
## cooldown. Commit is the last authority before payment, so it asks again.
func test_the_second_execution_to_commit_finds_the_cooldown_the_first_started() -> void:
	asc.set_attribute_base(MANA, 100.0)
	# ChannelingAbility rather than a probe with `channels` set: that field is
	# not exported, so it does not survive PER_EXECUTION's pack-then-instantiate
	# round trip and every fresh execution would come back finishing at once.
	# Both have to still be running when they commit, or there is no race.
	var channelled: ChannelingAbility = ChannelingAbility.new()
	channelled.name = "Channelled"
	channelled.ability_tags = [PROBE_TAG] as Array[StringName]
	channelled.instancing_policy = GameplayAbility.InstancingPolicy.PER_EXECUTION
	channelled.cooldown_effect = _cooldown()
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, channelled)

	var started: GameplayAbilityActivationResult = asc.ability_runtime.try_activate(spec.handle)
	var also: GameplayAbilityActivationResult = asc.ability_runtime.try_activate(spec.handle)
	assert_eq(
		started.status,
		GameplayAbilityActivationResult.Status.SUCCESS,
		"the first execution started"
	)
	assert_eq(
		also.status,
		GameplayAbilityActivationResult.Status.SUCCESS,
		"and so did the second: %s" % also.status
	)
	var running: Array[GameplayAbility] = spec.active_instances.duplicate()
	assert_eq(running.size(), 2, "both executions started before either committed")

	var first: AbilityCommitResult = running[0].commit_ability()
	var second: AbilityCommitResult = running[1].commit_ability()

	assert_eq(first.status, AbilityCommitResult.Status.SUCCESS, "the first one pays")
	assert_eq(
		second.status,
		AbilityCommitResult.Status.ON_COOLDOWN,
		"and the second finds the cooldown that payment started"
	)


## A commit that cannot finish leaves neither half of the price behind.
##
## The cost is affordable and the cooldown is not applicable, so the
## transaction has to undo the charge it had already made rather than bill for
## an ability that never went off.
func test_a_refused_commit_leaves_no_charge_and_no_cooldown() -> void:
	asc.set_attribute_base(MANA, 100.0)
	var broken: GameplayEffect = _cooldown()
	# INSTANT cannot hold a cooldown: it grants its tag and ends in the same
	# breath, so there would be nothing left to be on cooldown.
	broken.policy = GameplayEffect.DurationPolicy.INSTANT
	var ability: ProbeAbility = _granted(
		func _priced(probe: ProbeAbility) -> void:
			probe.costs = [_cost(20.0)] as Array[GameplayAbilityCost]
			probe.cooldown_effect = broken
	)
	asc.ability_runtime.try_activate(ability.current_spec.handle)

	var result: AbilityCommitResult = ability.commit_ability()

	assert_false(result.is_ok(), "the commit was refused: %s" % result.status)
	assert_almost_eq(_mana(), 100.0, 0.0001, "and nothing was charged")
	assert_false(asc.tags.has(COOLDOWN_TAG), "and no cooldown was started")
#endregion


#region When an activation is announced
## A synchronous ability is announced as activated before it is announced as
## ended.
##
## B09. The body ran inside the call that registered the activation, so an
## ability that finished immediately emitted `ability_ended` first and
## `ability_activated` afterwards: subscribers were told about the end of
## something they had not yet been told had begun.
func test_a_synchronous_ability_is_announced_started_before_it_is_announced_ended() -> void:
	var heard: Array[String] = []
	asc.ability_activated.connect(
		func _started(_handle: GameplayAbilityHandle, _instance: GameplayAbility) -> void:
			heard.append("activated")
	)
	asc.ability_runtime_ended.connect(
		func _ended(
			_handle: GameplayAbilityHandle,
			_instance: GameplayAbility,
			_cancelled: bool,
			_reason: GameplayAbilityTask.CancelReason
		) -> void:
			heard.append("ended")
	)
	var ability: ProbeAbility = _granted()

	asc.ability_runtime.try_activate(ability.current_spec.handle)

	var order: String = ", ".join(heard)
	assert_eq(order, "activated, ended", "in the order they happened")


## An ability that stays running is announced once, and not ended.
func test_an_ability_that_keeps_running_is_announced_once() -> void:
	var started: Array[String] = []
	asc.ability_activated.connect(
		func _on(_handle: GameplayAbilityHandle, _instance: GameplayAbility) -> void:
			started.append("activated")
	)
	var staying: StaysActiveAbility = StaysActiveAbility.new()
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, staying)

	asc.ability_runtime.try_activate(spec.handle)

	assert_eq(started.size(), 1, "announced exactly once")
	assert_true(spec.per_actor_instance.is_active, "and still running")


## A listener that cancels the activation stops the body from running.
##
## The whole reason the announcement moved. A subscriber is entitled to say
## "not this one" the moment it hears about an activation, and before this the
## body had already run by the time it was told.
func test_a_listener_that_cancels_on_activation_stops_the_body() -> void:
	var ability: ProbeAbility = _granted()
	asc.ability_activated.connect(
		func _cancel(_handle: GameplayAbilityHandle, instance: GameplayAbility) -> void:
			instance.abort_ability()
	)

	asc.ability_runtime.try_activate(ability.current_spec.handle)

	assert_eq(ability.activations, 0, "the body never ran")
	assert_false(ability.is_active, "and the ability is not running")


## A listener that removes the ability outright does not leave a body to run.
func test_a_listener_that_removes_the_ability_leaves_nothing_to_run() -> void:
	var ability: ProbeAbility = _granted()
	var handle: GameplayAbilityHandle = ability.current_spec.handle
	asc.ability_activated.connect(
		func _remove(removed: GameplayAbilityHandle, _instance: GameplayAbility) -> void:
			asc.ability_runtime.remove_ability(removed)
	)

	asc.ability_runtime.try_activate(handle)
	await get_tree().process_frame

	assert_null(asc.ability_runtime.get_spec(handle), "the ability is gone")
	assert_eq(asc.ability_runtime.specs().size(), 0, "and nothing was left behind")
#endregion
