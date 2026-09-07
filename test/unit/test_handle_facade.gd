## Asking the component about a thing by the receipt it gave out.
##
## A running ability is a Node that exists for as long as one activation lasts.
## The grant behind it outlives every one of them, and a caller holding an
## instance to remember which ability it meant is holding the shorter-lived of
## the two - so it works right up to the moment the ability finishes, and then
## the reference is to nothing.
##
## So the primary door takes a handle and answers with a result object, and the
## instance-shaped doors are kept for the callers that have one, holding nothing
## of their own. What is asserted here is that second half: both routes reach
## the same answer, because a wrapper with a copy of the decision in it is a
## second decision waiting to disagree.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ABILITY_TAG: StringName = &"Ability.Probe"
const BLOCKING_TAG: StringName = &"State.Silenced"
const INPUT_SLOT: int = 7

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Holder")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
func _granted(input_id: int = -1) -> GameplayAbilitySpec:
	return AbilityFactory.give(asc, Probe.build(ABILITY_TAG), 1.0, input_id)


## The running instance, as what it actually is.
func _probe(spec: GameplayAbilitySpec) -> ProbeAbility:
	return spec.per_actor_instance as ProbeAbility


## A grant that cannot start while the owner carries a tag.
func _blocked_while_silenced() -> GameplayAbilitySpec:
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [BLOCKING_TAG]
	var blocked: GameplayTagQuery = GameplayTagQuery.new()
	blocked.root = expression

	var probe: ProbeAbility = Probe.build(ABILITY_TAG)
	probe.activation_blocked_query = blocked
	return AbilityFactory.give(asc, probe, 1.0)


## A handle shaped like a real one that names nothing on this component.
func _names_nothing() -> GameplayAbilityHandle:
	var spec: GameplayAbilitySpec = _granted()
	var handle: GameplayAbilityHandle = spec.handle
	asc.remove_ability_handle(handle)
	return handle
#endregion


#region The receipt is the identity
## A handle answers with what it was given, and a spent one answers with nothing.
func test_a_handle_names_its_grant_and_a_spent_one_names_nothing() -> void:
	var spec: GameplayAbilitySpec = _granted()

	assert_same(asc.get_ability_spec(spec.handle), spec, "the grant behind the receipt")
	assert_null(asc.get_ability_spec(_names_nothing()), "and nothing behind a spent one")


## Taking a grant back by handle, and being told whether there was one.
func test_removing_by_handle_says_whether_there_was_anything_to_remove() -> void:
	var spec: GameplayAbilitySpec = _granted()

	assert_true(asc.remove_ability_handle(spec.handle), "it was granted")
	assert_null(asc.get_ability_spec(spec.handle), "and it is not any more")
	assert_false(asc.remove_ability_handle(spec.handle), "and a second time removes nothing")


## The deferred policy is reachable through the same door.
##
## A grant taken back while it is running is the case the policy exists for, and
## a facade that only exposed the immediate one would send a caller back to the
## runtime for the half that matters.
func test_a_removal_can_wait_for_what_is_running_to_finish() -> void:
	var spec: GameplayAbilitySpec = _granted()
	_probe(spec).channels = true
	asc.try_activate_ability_handle(spec.handle)

	var taken: bool = asc.remove_ability_handle(
		spec.handle, AbilityRuntime.AbilityRemovalPolicy.AFTER_ACTIVE_END
	)

	assert_true(taken, "the removal was accepted")
	assert_not_null(asc.get_ability_spec(spec.handle), "and it is still granted while it runs")
	assert_true(spec.pending_remove, "marked to go when it ends")
#endregion


#region Starting one, and being told what happened
## Activation answers with a result rather than a bool.
func test_activating_by_handle_answers_with_what_happened() -> void:
	var spec: GameplayAbilitySpec = _granted()

	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(spec.handle)

	assert_true(result.is_ok(), "it started")
	assert_same(result.handle, spec.handle, "and the result says which grant")
	assert_eq(_probe(spec).activations, 1, "the body ran once")


## A handle naming nothing is a refusal that says so, not a crash and not a
## silent false.
func test_activating_a_handle_that_names_nothing_says_which_refusal() -> void:
	var result: GameplayAbilityActivationResult = asc.try_activate_ability_handle(
		_names_nothing()
	)

	assert_eq(result.status, GameplayAbilityActivationResult.Status.SPEC_NOT_FOUND)


## The context door is the same door: what the caller hands in reaches the
## ability, and handing in nothing is an activation with nothing to say.
func test_the_activation_context_travels_through_the_handle_door() -> void:
	var checked: int = 0
	for with_event: bool in [true, false]:
		before_each()
		var spec: GameplayAbilitySpec = _granted()
		var context: GameplayAbilityActivationContext = null
		if with_event:
			var event: GameplayEventData = GameplayEventData.new()
			event.event_tag = &"Event.Struck"
			event.magnitude = 12.0
			context = GameplayAbilityActivationContext.from_gameplay_event(event)

		asc.try_activate_ability_handle(spec.handle, context)

		var carried: GameplayEventData = _probe(spec).get_activation_event()
		assert_eq(
			carried != null, with_event, "an event was carried only where one was handed in"
		)
		if with_event:
			assert_almost_eq(carried.magnitude, 12.0, 0.0001, "and it is the one handed in")
		checked += 1
	assert_eq(checked, 2, "both were asked for")
#endregion


#region The wrappers keep no copy of the decision
## Both doors answer the same, in both directions.
##
## The interesting row is the second: an ability that cannot start has one
## reason, and two doors that each worked it out separately would eventually
## disagree about it - which is a caller being told it may act and then refused.
##
##     [what state the owner is in, whether the ability can start]
func _both_verdicts() -> Array:
	return [
		["nothing in the way", false, true],
		["the owner is silenced", true, false],
	]


func test_the_handle_door_and_the_instance_door_give_one_answer() -> void:
	var rows: Array = _both_verdicts()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var silenced: bool = row[1]
		var expected: bool = row[2]

		before_each()
		var spec: GameplayAbilitySpec = _blocked_while_silenced()
		if silenced:
			asc.add_tag(BLOCKING_TAG)

		assert_eq(
			asc.can_activate_ability_handle(spec.handle), expected, "%s: by handle" % described
		)
		assert_eq(
			asc.can_activate_ability(spec.per_actor_instance),
			expected,
			"%s: and by instance" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "both states were offered")


## The refusal names the instance the caller asked about.
##
## A caller that handed in an instance is waiting to hear about that instance;
## one that handed in a handle gets the grant's own, which is what an activation
## nobody is holding an instance for already reports.
func test_a_refusal_names_whichever_instance_was_asked_about() -> void:
	var spec: GameplayAbilitySpec = _blocked_while_silenced()
	asc.add_tag(BLOCKING_TAG)
	var named: Array[GameplayAbility] = []
	asc.ability_activation_failed.connect(
		func(ability: GameplayAbility, _reason: AbilityRuntime.ActivationError) -> void:
			named.append(ability)
	)

	asc.can_activate_ability(spec.per_actor_instance, true)
	asc.can_activate_ability_handle(spec.handle, true)

	assert_eq(named.size(), 2, "both refusals were announced")
	assert_same(named[0], spec.per_actor_instance, "the instance that was handed in")
	assert_same(named[1], spec.per_actor_instance, "and the grant's own, which is the same one")


## Removing by instance goes through the handle door and leaves the same state.
func test_removing_by_instance_leaves_what_removing_by_handle_leaves() -> void:
	var spec: GameplayAbilitySpec = _granted()

	asc.remove_ability(spec.per_actor_instance)

	assert_null(asc.get_ability_spec(spec.handle), "the grant is gone either way")


## Removing nothing is not an error, whichever door it goes through.
func test_removing_nothing_is_not_an_error() -> void:
	asc.remove_ability(null)

	assert_eq(asc.ability_runtime.specs().size(), 0, "nothing was granted, nothing broke")
#endregion


#region Input, by grant rather than by instance
## A binding belongs to the grant: it answers the press whether or not anything
## of it is running at the moment the key goes down.
func test_an_input_binds_to_the_grant() -> void:
	var spec: GameplayAbilitySpec = _granted()

	assert_true(asc.bind_ability_handle_to_input(spec.handle, INPUT_SLOT), "bound")
	asc.ability_local_input_pressed(INPUT_SLOT)

	assert_eq(_probe(spec).activations, 1, "the press reached it")


func test_binding_a_handle_that_names_nothing_is_refused() -> void:
	assert_false(
		asc.bind_ability_handle_to_input(_names_nothing(), INPUT_SLOT),
		"nothing to bind the slot to"
	)
	assert_push_error("GAS_Engine: cannot bind an ability that was never granted to this ASC.")
#endregion


#region The effect side of the same idea
## An effect handle resolves to what is running, and a spent one to nothing.
func test_an_effect_handle_names_what_is_running() -> void:
	var no_modifiers: Array[GameplayEffectModifier] = []
	var active: ActiveGameplayEffect = EffectFactory.apply(
		asc, EffectFactory.infinite(no_modifiers)
	)

	assert_same(asc.get_active_effect(active.handle), active, "the effect behind the receipt")

	asc.remove_active_effect_by_handle(active.handle)

	assert_null(asc.get_active_effect(active.handle), "and nothing behind a spent one")
#endregion
