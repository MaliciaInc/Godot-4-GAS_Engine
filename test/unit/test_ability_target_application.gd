## Firing one effect at several targets, and being told what became of each.
##
## A count of successes cannot distinguish the three ways a target drops out. A
## scene wired without an ability system is a bug in the scene; a target that
## refused the effect is gameplay working; two colliders that turn out to be one
## actor is neither, and silently applying twice there would double every area
## effect for anything with more than one hitbox.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")

const TOLERANCE: float = 0.0001
const PROBE_TAG: StringName = &"Ability.Probe"
const IMMUNE: StringName = &"State.Immune"
const HEALTH: StringName = &"health"
const DAMAGE: float = -10.0

var caster: ASCFixture = null
var ability: ProbeAbility = null

## The source the target reported for the effect it received.
var seen_source: AbilitySystemComponent = null


func before_each() -> void:
	caster = Fixture.create("Caster")
	add_child_autofree(caster.owner)
	ability = Probe.build(PROBE_TAG)
	caster.asc.grant_ability(ability)
	seen_source = null


func after_each() -> void:
	caster = null
	ability = null


#region Builders
## A target actor: a plain node with an ability system beside its colliders.
func _victim(actor_name: String) -> ASCFixture:
	var victim: ASCFixture = Fixture.create(actor_name)
	add_child_autofree(victim.owner)
	return victim


func _collider(parent: Node, collider_name: String) -> Node:
	var collider: Node = Node.new()
	collider.name = collider_name
	parent.add_child(collider)
	return collider


func _targets(nodes: Array[Node]) -> GameplayAbilityTargetData:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_overlap(nodes)
	return data


func _damage() -> GameplayEffect:
	return Factory.instant([Factory.add(HEALTH, DAMAGE)])


func _on_effect_received(source_asc: AbilitySystemComponent, _spec: GameplayEffectSpec) -> void:
	seen_source = source_asc
#endregion


#region Counting honestly
func test_unusable_arguments_still_answer_with_a_result() -> void:
	var empty: GameplayAbilityTargetData = GameplayAbilityTargetData.new()

	var no_effect: GameplayTargetApplicationResult = ability.apply_effect_to_targets(null, empty)
	assert_eq(no_effect.attempted_targets, 0, "nothing was attempted")
	assert_eq(no_effect.applied_count(), 0, "and nothing applied")

	var no_data: GameplayTargetApplicationResult = ability.apply_effect_to_targets(_damage(), null)
	assert_eq(no_data.applied_count(), 0, "a caller never has to check for null")


func test_a_target_without_an_ability_system_is_named_rather_than_missed() -> void:
	var scenery: Node = Node.new()
	scenery.name = "Crate"
	add_child_autofree(scenery)
	var nodes: Array[Node] = [scenery]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		_damage(), _targets(nodes)
	)

	assert_eq(result.attempted_targets, 1, "it was attempted")
	assert_eq(result.applied_count(), 0, "and nothing was applied")
	assert_eq(result.missing_asc_targets.size(), 1, "reported as a wiring problem")
	assert_eq(result.rejected_targets.size(), 0, "not as a refusal, which it was not")


## Two hitboxes on one actor are one target.
func test_two_colliders_on_one_actor_are_charged_once() -> void:
	var victim: ASCFixture = _victim("Victim")
	victim.set_base(HEALTH, 100.0)
	var nodes: Array[Node] = [
		_collider(victim.owner, "Torso"), _collider(victim.owner, "Head")
	]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		_damage(), _targets(nodes)
	)

	assert_eq(result.attempted_targets, 2, "two colliders were offered")
	assert_eq(result.applied_count(), 1, "and resolved to one actor")
	assert_almost_eq(victim.base_of(HEALTH), 90.0, TOLERANCE, "hit once, not twice")


func test_a_target_that_refuses_is_reported_as_refused() -> void:
	var victim: ASCFixture = _victim("Immune")
	victim.set_base(HEALTH, 100.0)
	victim.asc.add_tag(IMMUNE)
	var blocked: GameplayEffect = Factory.blocked_by(_damage(), [IMMUNE])
	var nodes: Array[Node] = [victim.owner]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		blocked, _targets(nodes)
	)

	assert_eq(result.rejected_targets.size(), 1, "the target refused it")
	assert_eq(result.missing_asc_targets.size(), 0, "and it was certainly found")
	assert_eq(result.applied_count(), 0, "so nothing landed")
	assert_almost_eq(victim.base_of(HEALTH), 100.0, TOLERANCE, "and it took no damage")
#endregion


#region Several targets at once
func test_each_target_is_evaluated_against_its_own_state() -> void:
	var healthy: ASCFixture = _victim("Healthy")
	var hurt: ASCFixture = _victim("Hurt")
	healthy.set_base(HEALTH, 100.0)
	hurt.set_base(HEALTH, 40.0)
	var nodes: Array[Node] = [healthy.owner, hurt.owner]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		_damage(), _targets(nodes)
	)

	assert_eq(result.applied_count(), 2, "both were reached")
	assert_almost_eq(healthy.base_of(HEALTH), 90.0, TOLERANCE, "the first took its own damage")
	assert_almost_eq(hurt.base_of(HEALTH), 30.0, TOLERANCE, "and the second took its own")


## The source of an effect is found by the same search as any other component.
##
## The ASC used to answer this with a lookup of its own: a direct child under
## the conventional name, unchecked. A node merely called that would have been
## handed back as the source, and a caster whose component sits beside a
## collider would not have been found at all.
func test_the_source_of_an_effect_is_found_by_the_same_search() -> void:
	var victim: ASCFixture = _victim("Victim")
	victim.set_base(HEALTH, 100.0)
	victim.asc.effect_received.connect(_on_effect_received)
	var nodes: Array[Node] = [victim.owner]

	ability.apply_effect_to_targets(_damage(), _targets(nodes))

	assert_eq(seen_source, caster.asc, "the source resolved to the caster's own component")


func test_the_result_separates_the_three_ways_a_target_drops_out() -> void:
	var reached: ASCFixture = _victim("Reached")
	var refusing: ASCFixture = _victim("Refusing")
	reached.set_base(HEALTH, 100.0)
	refusing.asc.add_tag(IMMUNE)
	var scenery: Node = Node.new()
	scenery.name = "Crate"
	add_child_autofree(scenery)
	var nodes: Array[Node] = [reached.owner, refusing.owner, scenery]

	var result: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		Factory.blocked_by(_damage(), [IMMUNE]), _targets(nodes)
	)

	assert_eq(result.attempted_targets, 3, "three were offered")
	assert_eq(result.applied_targets.size(), 1, "one was reached and accepted")
	assert_eq(result.rejected_targets.size(), 1, "one was reached and refused")
	assert_eq(result.missing_asc_targets.size(), 1, "and one could not be reached at all")
	assert_eq(result.applied_count(), 1, "the handles agree with the accepted count")
#endregion
