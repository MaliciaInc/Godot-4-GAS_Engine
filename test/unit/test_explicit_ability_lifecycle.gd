## When an ability ends, whether it may be started again, and what it is told.
##
## Returning from `_activate_ability()` used to end the ability, always. That is
## right for an ability that does its work and is done, and wrong for one that
## starts something and finishes later - a channel, a projectile in flight, a
## wait on an event - which had to stay suspended inside its own activation
## function to stay alive. So the ability says which it is, and the default says
## what it always said, because turning it off underneath an existing project
## would leave every ability in it running forever.
##
## Pressing an ability that is already running was refused, always. That is
## right for one that would stack and wrong for one that should replace itself,
## so that is said too - and replacing ends the activation in flight rather than
## cancelling it, because the player asked for this.
##
## And an ability is now told things rather than left to discover them: that it
## was granted, that it is being taken away, that the body it happens to has
## been exchanged. The fourth hook is a question rather than a notification -
## whether it may be cancelled at all - because an uninterruptible finisher is a
## thing games have.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Lifecycle = preload("res://test/fixtures/explicit_lifecycle_ability.gd")

const ABILITY_TAG: StringName = &"Ability.Explicit"
const CANCELS: StringName = &"Ability.Canceller"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Owner")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## Grant one, configured before the grant because that is what is captured.
func _granted(configure: Callable = Callable()) -> GameplayAbilitySpec:
	var ability: ExplicitLifecycleAbility = Lifecycle.new()
	ability.name = "Explicit"
	ability.ability_tags = [ABILITY_TAG] as Array[StringName]
	if configure.is_valid():
		configure.call(ability)
	return AbilityFactory.give(asc, ability)


func _instance(spec: GameplayAbilitySpec) -> ExplicitLifecycleAbility:
	return spec.per_actor_instance as ExplicitLifecycleAbility


func _activate(spec: GameplayAbilitySpec) -> GameplayAbilityActivationResult:
	return asc.ability_runtime.try_activate(spec.handle)
#endregion


#region When it ends
## Whether returning from the activation function ends the ability.
##
## Both rows, because either alone is satisfied by the wrong thing: an ability
## that never ends passes the second row, and one that always ends passes the
## first. What separates them is the flag, and the default is the first.
##
##     [what it is, auto end, still running afterwards]
const ENDINGS: Array = [
	["the default, which is what it always did", true, false],
	["one that finishes itself later", false, true],
]


func test_an_ability_ends_when_it_returns_only_if_it_says_so() -> void:
	var checked: int = 0
	for row: Array in ENDINGS:
		var described: String = row[0]
		var auto_end: bool = row[1]
		var still_running: bool = row[2]

		before_each()
		var spec: GameplayAbilitySpec = _granted(
			func _configure(ability: ExplicitLifecycleAbility) -> void:
				ability.auto_end_on_activate_return = auto_end
		)
		_activate(spec)

		assert_eq(_instance(spec).activations, 1, "%s: it ran" % described)
		assert_eq(
			_instance(spec).is_active, still_running, "%s: and what it left" % described
		)
		checked += 1
	assert_eq(checked, ENDINGS.size(), "both endings were asked for")


## One that finishes itself later is finished by saying so.
func test_an_ability_that_outlives_its_activation_ends_when_it_says() -> void:
	var spec: GameplayAbilitySpec = _granted(
		func _configure(ability: ExplicitLifecycleAbility) -> void:
			ability.auto_end_on_activate_return = false
	)
	_activate(spec)
	assert_true(_instance(spec).is_active, "still running")

	_instance(spec).end_ability(false)

	assert_false(_instance(spec).is_active, "and finished when it said it was")
#endregion


#region Starting it again
## Pressing an ability that is already running: refused, or replaced.
##
##     [what it is, retrigger, second attempt's status, times the body ran]
func _retriggers() -> Array:
	return [
		[
			"refused, which is the default", false,
			GameplayAbilityActivationResult.Status.ALREADY_ACTIVE, 1,
		],
		[
			"replaced, when it says so", true,
			GameplayAbilityActivationResult.Status.SUCCESS, 2,
		],
	]


func test_activating_a_running_ability_is_refused_unless_it_says_otherwise() -> void:
	var rows: Array = _retriggers()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var retrigger: bool = row[1]
		var expected: GameplayAbilityActivationResult.Status = row[2]
		var ran: int = row[3]

		before_each()
		var spec: GameplayAbilitySpec = _granted(
			func _configure(ability: ExplicitLifecycleAbility) -> void:
				ability.auto_end_on_activate_return = false
				ability.retrigger_while_active = retrigger
		)
		_activate(spec)
		assert_true(_instance(spec).is_active, "%s: the first one is running" % described)

		var again: GameplayAbilityActivationResult = _activate(spec)

		assert_eq(again.status, expected, "%s: the second attempt" % described)
		assert_eq(_instance(spec).activations, ran, "%s: times it ran" % described)
		checked += 1
	assert_eq(checked, rows.size(), "both answers were asked for")


## Replacing announces one ending and one beginning, not two beginnings.
##
## The ending is what makes it a replacement rather than a stack: anything
## counting how many of this ability are running has to come back to one.
func test_retriggering_ends_what_was_running_before_starting_again() -> void:
	var heard: Array[String] = []
	asc.ability_activated.connect(
		func _started(_handle: GameplayAbilityHandle, _instance: GameplayAbility) -> void:
			heard.append("started")
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
	var spec: GameplayAbilitySpec = _granted(
		func _configure(ability: ExplicitLifecycleAbility) -> void:
			ability.auto_end_on_activate_return = false
			ability.retrigger_while_active = true
	)

	_activate(spec)
	_activate(spec)

	assert_eq(
		", ".join(heard), "started, ended, started", "one ending between two beginnings"
	)
	assert_true(_instance(spec).is_active, "and one of it is running")
#endregion


#region What it is told
## Granting tells it, and taking it away tells it before anything is severed.
func test_an_ability_is_told_when_it_is_granted_and_when_it_is_taken_away() -> void:
	var spec: GameplayAbilitySpec = _granted()
	var ability: ExplicitLifecycleAbility = _instance(spec)
	assert_eq(", ".join(ability.told), "granted", "told once, on the grant")

	asc.ability_runtime.remove_ability(spec.handle)

	# "removed" rather than "removed after being cut loose": the ability records
	# what it could still reach when it was told, which is the only moment that
	# can be observed - afterwards everything is severed either way.
	assert_eq(
		", ".join(ability.told),
		"granted, removed",
		"told on the way out, while it could still reach what it owned"
	)


## A body swap reaches every granted ability directly.
func test_an_ability_is_told_when_the_body_it_happens_to_changes() -> void:
	var first: Node = Node.new()
	first.name = "First"
	add_child_autofree(first)
	var second: Node = Node.new()
	second.name = "Second"
	add_child_autofree(second)
	asc.init_ability_actor_info(fixture.owner, first)
	var ability: ExplicitLifecycleAbility = _instance(_granted())

	asc.init_ability_actor_info(fixture.owner, second)

	assert_true(
		ability.told.has("avatar First -> Second"),
		"it was told which body it moved to: %s" % [ability.told]
	)


## An ability that refuses to be cancelled is not cancelled by another's tags.
##
## Both directions, because "it survived" is also true of a cancel that never
## reached it: the same ability with the same canceller has to go down when it
## does not refuse.
func test_an_ability_that_refuses_cancellation_survives_another_ability() -> void:
	var checked: int = 0
	for cancellable: bool in [true, false]:
		before_each()
		var spec: GameplayAbilitySpec = _granted(
			func _configure(ability: ExplicitLifecycleAbility) -> void:
				ability.auto_end_on_activate_return = false
		)
		_activate(spec)
		_instance(spec).cancellable = cancellable
		assert_true(_instance(spec).is_active, "it is running")

		asc.ability_runtime.tag_semantics.cancel_with_tags(
			[ABILITY_TAG] as Array[StringName]
		)

		assert_eq(
			_instance(spec).is_active,
			not cancellable,
			"cancellable=%s: what the cancel left" % cancellable
		)
		checked += 1
	assert_eq(checked, 2, "both answers were asked for")
#endregion


#region Keeping no state
## Two concurrent NON_INSTANCED activations do not share a Node.
##
## The whole point of the policy. Sharing one mutable Node between them is what
## would give each the other's state, so what is asserted is that there is no
## shared Node to give: neither activation is the spec's instance, and they are
## not each other.
func test_two_non_instanced_activations_share_nothing() -> void:
	var ability: ExplicitLifecycleAbility = Lifecycle.new()
	ability.name = "Stateless"
	ability.ability_tags = [ABILITY_TAG] as Array[StringName]
	ability.instancing_policy = GameplayAbility.InstancingPolicy.NON_INSTANCED
	ability.auto_end_on_activate_return = false
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, ability)

	var first: GameplayAbilityActivationResult = _activate(spec)
	var second: GameplayAbilityActivationResult = _activate(spec)

	assert_eq(first.status, GameplayAbilityActivationResult.Status.SUCCESS, "one ran")
	assert_eq(second.status, GameplayAbilityActivationResult.Status.SUCCESS, "and another")
	assert_ne(first.instance, second.instance, "on Nodes of their own")
	assert_null(spec.per_actor_instance, "and neither was adopted by the grant")
#endregion
