## An area effect landing on two, and each of them knowing only what hit it.
##
## The phase states the case plainly: two victims, and A's hit never appears in
## B. What was there before failed it in both directions at once - the copy an
## application is made from drops target data entirely, so neither victim was
## told about anybody else and neither was told about itself either. An ability
## asking "did this hit my head" got nothing to ask.
##
## Both halves are asserted, because fixing one by breaking the other is the
## easy mistake: hand every application the whole aim and every victim knows
## about the others.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ATTACK: StringName = &"attack"
const ABILITY_TAG: StringName = &"Ability.Area"

var caster: ASCFixture = null
var first: ASCFixture = null
var second: ASCFixture = null


func before_each() -> void:
	caster = Fixture.create("Caster")
	first = Fixture.create("Victim")
	second = Fixture.create("Bystander")
	for one: ASCFixture in [caster, first, second]:
		add_child_autofree(one.owner)
		one.asc.set_process(false)


func after_each() -> void:
	caster = null
	first = null
	second = null


#region Getting there
## An aim that touched both of them.
func _aimed_at_both() -> GameplayAbilityTargetData:
	var aim: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	aim.append_node(first.owner)
	aim.append_node(second.owner)
	return aim


func _context_aimed_at_both() -> GameplayEffectContext:
	var context: GameplayEffectContext = GameplayEffectContext.new(
		caster.owner, caster.owner
	)
	context.target_data = _aimed_at_both()
	return context
#endregion


#region One victim's share
## A copy for one node keeps that node and nothing else.
func test_a_copy_for_one_node_keeps_only_that_node() -> void:
	var aim: GameplayAbilityTargetData = _aimed_at_both()

	var theirs: GameplayAbilityTargetData = aim.copied(first.owner)

	assert_eq(theirs.get_target_nodes(), [first.owner] as Array[Node], "only theirs")
	assert_eq(aim.get_target_nodes().size(), 2, "and the aim it came from is untouched")


## A copy of the whole thing keeps the whole thing.
func test_a_copy_of_the_whole_aim_keeps_all_of_it() -> void:
	var aim: GameplayAbilityTargetData = _aimed_at_both()

	var whole: GameplayAbilityTargetData = aim.copied()

	assert_eq(whole.get_target_nodes().size(), 2, "both")
	assert_not_same(whole, aim, "and it is its own")


## A copy for something that was never aimed at is empty rather than everything.
func test_a_copy_for_something_never_aimed_at_is_empty() -> void:
	var aim: GameplayAbilityTargetData = _aimed_at_both()

	assert_false(aim.copied(caster.owner).has_targets(), "the caster was not a target")
	assert_eq(aim.copied(null).get_target_nodes().size(), 2, "and null is not a filter")


## A copy for one node keeps that node's hits, and only those.
##
## The half a "which targets" check cannot see. Every hit carries where it
## landed and on what, and this is what a "did that hit my head" question is
## asked of - so a victim holding somebody else's hits answers yes about a shape
## that is not theirs.
func test_a_copy_for_one_node_keeps_only_that_node_s_hits() -> void:
	var aim: GameplayAbilityTargetData = _aimed_at_both()
	assert_eq(aim.get_all_hits().size(), 2, "one hit each to begin with")

	var theirs: GameplayAbilityTargetData = aim.copied(first.owner)

	assert_eq(theirs.get_all_hits().size(), 1, "one hit, not both")
	assert_same(theirs.get_all_hits()[0].collider, first.owner, "and it is theirs")
	assert_eq(
		theirs.get_hits_for_node(second.owner).size(), 0,
		"the other victim's hit is nowhere in it"
	)


## And the case the phase names, at the level a hit is asked about.
func test_one_victims_application_carries_none_of_the_others_hits() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(
		caster.asc, Probe.build(ABILITY_TAG)
	)
	var payload: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)

	var landed: GameplayTargetApplicationResult = spec.per_actor_instance.apply_effect_to_targets(
		payload, _aimed_at_both()
	)

	var checked: int = 0
	for applied: GameplayEffectApplicationResult in landed.applications:
		var aimed: GameplayAbilityTargetData = applied.active_effect.spec.context.target_data
		var theirs: Node = aimed.get_target_nodes()[0]
		var other: Node = second.owner if theirs == first.owner else first.owner

		assert_eq(aimed.get_all_hits().size(), 1, "one hit in this application")
		assert_eq(
			aimed.get_hits_for_node(other).size(), 0,
			"and none of it belongs to the other victim"
		)
		checked += 1
	assert_eq(checked, 2, "both applications were looked at")


## Two copies never share what either of them does next.
##
## Target data is mutable - a channelled ability drops a target that walked out
## of the area - and two victims holding one object is either of them changing
## what the other sees.
func test_two_copies_share_nothing_that_either_of_them_changes() -> void:
	var aim: GameplayAbilityTargetData = _aimed_at_both()
	var theirs: GameplayAbilityTargetData = aim.copied()
	var ours: GameplayAbilityTargetData = aim.copied()

	theirs.force_remove_target(first.owner)

	assert_eq(theirs.get_target_nodes().size(), 1, "one of them dropped a target")
	assert_eq(ours.get_target_nodes().size(), 2, "and the other still has both")
	assert_eq(aim.get_target_nodes().size(), 2, "as does the aim they came from")
#endregion


#region A context aimed at one of several
## The copy an application is made from carries no aim at all.
##
## Which is right: an application is one victim's, and the aim it came from was
## several victims'. What replaces it is `derive_for_target()`.
func test_an_application_copy_carries_no_aim() -> void:
	var copy: GameplayEffectContext = _context_aimed_at_both().create_application_copy()

	assert_not_null(copy, "it copied")
	assert_false(copy.has_targets(), "and carries nobody's aim")


## Deriving for a target carries the origin, the payloads, and that aim.
func test_deriving_for_a_target_carries_the_origin_and_that_aim() -> void:
	var context: GameplayEffectContext = _context_aimed_at_both()
	var theirs: GameplayAbilityTargetData = context.target_data.copied(first.owner)

	var derived: GameplayEffectContext = context.derive_for_target(theirs)

	assert_same(derived.instigator, caster.owner, "who cast it")
	assert_eq(derived.get_target_nodes(), [first.owner] as Array[Node], "and who this is for")
	assert_not_same(derived.target_data, theirs, "holding its own copy of it")


## Deriving for nothing is deriving a context with no aim, not a failure.
func test_deriving_for_nothing_carries_no_aim() -> void:
	var derived: GameplayEffectContext = _context_aimed_at_both().derive_for_target(null)

	assert_not_null(derived, "still a context")
	assert_false(derived.has_targets(), "with nothing aimed at")
#endregion


#region The case the phase names
## An area effect on two victims: each one is told what hit it, and nothing
## about the other.
func test_an_area_effect_never_tells_one_victim_about_the_other() -> void:
	for one: ASCFixture in [first, second]:
		one.set_base(ATTACK, 100.0)
	var spec: GameplayAbilitySpec = AbilityFactory.give(
		caster.asc, Probe.build(ABILITY_TAG)
	)
	var ability: GameplayAbility = spec.per_actor_instance
	var payload: GameplayEffect = EffectFactory.infinite(
		[EffectFactory.add(ATTACK, -10.0)] as Array[GameplayEffectModifier]
	)

	var landed: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		payload, _aimed_at_both()
	)

	assert_eq(landed.applied_targets.size(), 2, "it landed on both")
	var checked: int = 0
	for applied: GameplayEffectApplicationResult in landed.applications:
		var aimed: GameplayEffectContext = applied.active_effect.spec.context
		assert_eq(aimed.get_target_nodes().size(), 1, "each application knows one target")
		checked += 1
	assert_eq(checked, 2, "both applications were looked at")


## And the one it knows is itself.
func test_each_victim_is_told_about_itself() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(
		caster.asc, Probe.build(ABILITY_TAG)
	)
	var payload: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)

	var landed: GameplayTargetApplicationResult = spec.per_actor_instance.apply_effect_to_targets(
		payload, _aimed_at_both()
	)

	var told: Array[Node] = []
	for applied: GameplayEffectApplicationResult in landed.applications:
		told.append_array(applied.active_effect.spec.context.get_target_nodes())

	# As a set rather than in order: which application ran first is the order the
	# aim listed them in, and asserting that would be asserting something this is
	# not about.
	assert_eq(told.size(), 2, "two applications, one target named by each")
	assert_true(told.has(first.owner), "the victim was told about itself")
	assert_true(told.has(second.owner), "and the bystander about itself")


## Neither of them holds the other's object either.
##
## The half that a "one target each" check cannot see: two applications could
## each name one victim and still be pointing at the very same target data.
func test_no_two_applications_share_one_aim() -> void:
	var spec: GameplayAbilitySpec = AbilityFactory.give(
		caster.asc, Probe.build(ABILITY_TAG)
	)
	var payload: GameplayEffect = EffectFactory.infinite(
		[] as Array[GameplayEffectModifier]
	)

	var landed: GameplayTargetApplicationResult = spec.per_actor_instance.apply_effect_to_targets(
		payload, _aimed_at_both()
	)

	var held: Array[GameplayAbilityTargetData] = []
	for applied: GameplayEffectApplicationResult in landed.applications:
		held.append(applied.active_effect.spec.context.target_data)
	assert_eq(held.size(), 2, "two applications")
	assert_not_same(held[0], held[1], "and two aims")
#endregion
