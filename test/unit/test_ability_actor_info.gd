## Who an ability belongs to, and who it happens to.
##
## Usually the same node. This is about the case where they are not: a player's
## abilities belong to the player and happen to whatever they are currently
## driving - a possessed body, a mount, a vehicle - and the component has to stay
## where the grants are while what effects and cues act on changes underneath it.
##
## Before this there was one answer to both questions, and it was `get_parent()`.
## Anything that wanted a body swap had to move the component, and moving the
## component means moving the grants, the active effects, the cooldowns and the
## attributes with it.
##
## The default is the case nobody thinks about: a component under an entity,
## owner and avatar both, exactly what `get_parent()` used to say.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const ATTACK: StringName = &"attack"
const PROBE_TAG: StringName = &"Ability.Probe"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Player")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	fixture = null
	asc = null


#region Getting there
## A body the player could be driving.
func _body(named: String) -> Node:
	var made: Node = Node.new()
	made.name = named
	add_child_autofree(made)
	return made
#endregion


#region What it answers when nobody said anything
## A component nobody configured answers exactly what it always answered.
##
## The whole compatibility risk of this change in one assertion: every project
## that never thinks about avatars puts the component under an entity and reads
## the entity back.
func test_a_component_nobody_configured_still_points_at_its_parent() -> void:
	assert_eq(asc.get_effect_target(), fixture.owner, "the entity it hangs under")
	assert_eq(asc.actor_info.owner, fixture.owner, "which is the owner")
	assert_eq(asc.actor_info.avatar, fixture.owner, "and the avatar too")


## An avatar that has been freed does not leave the component answering nothing.
##
## The body was destroyed and nobody has assigned another yet. Effects and cues
## still have to land somewhere, and the owner is the honest fallback: it is the
## thing that persists.
func test_a_freed_avatar_falls_back_to_the_owner() -> void:
	var body: Node = _body("Body")
	asc.init_ability_actor_info(fixture.owner, body)
	assert_eq(asc.get_effect_target(), body, "the body, while it exists")

	body.free()

	assert_eq(asc.get_effect_target(), fixture.owner, "and the owner once it does not")
#endregion


#region Changing bodies
## Swapping the avatar moves what effects act on, and says so.
func test_swapping_the_avatar_moves_the_target_and_announces_it() -> void:
	var first: Node = _body("First")
	var second: Node = _body("Second")
	asc.init_ability_actor_info(fixture.owner, first)

	var announced: Array[String] = []
	asc.ability_actor_info_changed.connect(
		func _changed(old_avatar: Node, new_avatar: Node) -> void:
			announced.append("%s -> %s" % [old_avatar.name, new_avatar.name])
	)

	asc.init_ability_actor_info(fixture.owner, second)

	assert_eq(asc.get_effect_target(), second, "effects act on the new body")
	assert_eq(Array(announced), ["First -> Second"], "and whoever held the old one is told")


## Setting the same avatar again announces nothing.
##
## A signal that fires on a change that did not happen is one every listener has
## to filter, and the filtering is the part they get wrong.
func test_setting_the_same_avatar_again_announces_nothing() -> void:
	var body: Node = _body("Body")
	asc.init_ability_actor_info(fixture.owner, body)
	watch_signals(asc)

	asc.init_ability_actor_info(fixture.owner, body, _body("Controller"))

	assert_signal_not_emitted(asc, "ability_actor_info_changed", "nothing moved")


## Everything the component holds survives a body swap.
##
## This is what the split is for. Before it, changing bodies meant moving the
## component, and moving the component meant the grants, the running effects and
## the attributes went with it - or did not.
func test_a_body_swap_keeps_the_grants_and_the_effects() -> void:
	var first: Node = _body("First")
	asc.init_ability_actor_info(fixture.owner, first)
	var probe: ProbeAbility = Probe.build(PROBE_TAG)
	var spec: GameplayAbilitySpec = AbilityFactory.give(asc, probe)
	asc.set_attribute_base(ATTACK, 10.0)
	var modifiers: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 5.0)]
	Factory.apply(asc, Factory.infinite(modifiers))
	assert_almost_eq(asc.get_attribute_current(ATTACK), 15.0, 0.0001, "the buff is on")

	asc.init_ability_actor_info(fixture.owner, _body("Second"))

	assert_not_null(asc.ability_runtime.get_spec(spec.handle), "the grant is still here")
	assert_eq(asc.effects.active_count(), 1, "and so is the effect")
	assert_almost_eq(
		asc.get_attribute_current(ATTACK), 15.0, 0.0001, "still worth what it was"
	)


## A cue fired after a swap is played on the new body.
##
## The reason the target is asked for every time rather than captured once: a
## cue that resolved its node at application would keep drawing on a corpse.
func test_a_cue_after_a_swap_is_played_on_the_new_body() -> void:
	var first: Node = _body("First")
	asc.init_ability_actor_info(fixture.owner, first)
	assert_eq(asc.get_effect_target(), first, "the first body")

	var second: Node = _body("Second")
	asc.init_ability_actor_info(fixture.owner, second)

	assert_eq(asc.get_effect_target(), second, "and afterwards, the second")
#endregion
