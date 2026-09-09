## The two questions that used to read every effect on a character, and what
## they read now.
##
## Structural rather than timed. A threshold in milliseconds is a fact about one
## machine and a suite that failed on somebody's laptop for it is a suite people
## learn to ignore; how many effects a search compared is the same number on
## every machine, and it is the number that was growing.
##
## What is asserted is that the answers did not change. Each indexed lookup is
## checked against the scan it replaced, over the same state, in the same order:
## an index that is faster and wrong is worse than the walk it replaced.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

## The scale the phase names for the stack search.
const CROWD: int = 1000

## What "much less than the crowd" means here, said as a number rather than a
## ratio: a bucket holds the effects that share a definition, and a crowd of
## distinct definitions puts one in each.
const AT_MOST_EXAMINED: int = 2

const BURNING: StringName = &"State.Burning"
const FAMILY: StringName = &"State"
const ELSEWHERE: StringName = &"Status.Immune"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	fixture = Fixture.create("Crowded")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	asc.effects.index.forget_counters()


func after_each() -> void:
	fixture = null
	asc = null


#region Building a crowd
## One effect per definition, none of them stacking with any other.
##
## Distinct definitions on purpose: that is the case the old search was worst
## at, because every one of them had to be compared and none of them could be
## the answer.
func _crowd(size: int) -> void:
	for index: int in size:
		var nothing: Array[GameplayEffectModifier] = []
		asc.apply_gameplay_effect(EffectFactory.infinite(nothing), asc, 1.0)


## An effect that stacks by target, so a second application joins the first.
func _stackable() -> GameplayEffect:
	var nothing: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = EffectFactory.infinite(nothing)
	effect.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_TARGET
	effect.stack_limit_count = 0
	return effect


## What `find_candidate` answered before there was an index: the whole list,
## in application order, first match wins.
func _scanned(spec: GameplayEffectSpec) -> ActiveGameplayEffect:
	var effect: GameplayEffect = spec.effect_def
	if effect.stacking_type == GameplayEffect.StackingType.NONE:
		return null
	for active: ActiveGameplayEffect in asc.effects.active_effects():
		if active.get_effect_def() != effect:
			continue
		if effect.stacking_type == GameplayEffect.StackingType.AGGREGATE_BY_SOURCE:
			if spec.source_asc == null or active.spec.source_asc != spec.source_asc:
				continue
		return active
	return null
#endregion


#region The stack search
## A thousand effects on a character, and the search for a stack compares two.
func test_a_stack_search_does_not_read_a_crowd_it_cannot_join() -> void:
	var stackable: GameplayEffect = _stackable()
	asc.apply_gameplay_effect(stackable, asc, 1.0)
	_crowd(CROWD)
	assert_gt(asc.effects.active_count(), CROWD, "there is a crowd to not read")

	asc.effects.index.forget_counters()
	var joined: ActiveGameplayEffect = asc.apply_gameplay_effect(stackable, asc, 1.0)

	assert_not_null(joined, "the application landed")
	assert_eq(joined.stack_count, 2, "on the stack that was already there")
	assert_gt(
		asc.effects.index.stack_candidates_examined, 0,
		"the search went through the index rather than reading the list itself"
	)
	assert_lt(
		asc.effects.index.stack_candidates_examined, AT_MOST_EXAMINED + 1,
		"and compared what shares its definition rather than the crowd"
	)


## The indexed answer is the answer the scan gives, over the same state.
##
## Both stacking rules and the case that stacks with nothing, because the three
## are different questions and an index that got one of them right would look
## right until somebody used another.
func test_the_indexed_candidate_is_the_one_the_scan_finds() -> void:
	var other: ASCFixture = Fixture.create("Elsewhere")
	add_child_autofree(other.owner)

	var by_target: GameplayEffect = _stackable()
	var by_source: GameplayEffect = _stackable()
	by_source.stacking_type = GameplayEffect.StackingType.AGGREGATE_BY_SOURCE
	var nothing: Array[GameplayEffectModifier] = []
	var never: GameplayEffect = EffectFactory.infinite(nothing)

	asc.apply_gameplay_effect(by_target, asc, 1.0)
	asc.apply_gameplay_effect(by_source, other.asc, 1.0)
	asc.apply_gameplay_effect(never, asc, 1.0)
	_crowd(20)

	for described: Array in [
		["joining by target", by_target, asc],
		["joining by source, from the same source", by_source, other.asc],
		["joining by source, from a different one", by_source, asc],
		["not stacking at all", never, asc],
	]:
		var what: String = described[0]
		var effect: GameplayEffect = described[1]
		var source: AbilitySystemComponent = described[2]

		var spec: GameplayEffectSpec = GameplayEffectSpec.new(
			effect, GameplayEffectContext.new(source.get_effect_target()), 1.0
		)
		spec.source_asc = source

		assert_same(
			asc.effects.stacking.find_candidate(spec), _scanned(spec),
			"the index and the scan agree about %s" % what
		)
#endregion


## A thousand effects on a character, and an application asks one about immunity.
##
## The third traversal, and the one that dominated: every application asked
## every active effect whether it granted immunity, and almost none of them do.
func test_an_application_asks_only_what_grants_immunity() -> void:
	asc.apply_gameplay_effect(_granting_immunity(), asc, 1.0)
	_crowd(CROWD)

	asc.effects.index.forget_counters()
	var nothing: Array[GameplayEffectModifier] = []
	asc.apply_gameplay_effect(EffectFactory.infinite(nothing), asc, 1.0)

	assert_eq(
		asc.effects.index.immunities_examined, 1,
		"the one that grants immunity, and none of the crowd"
	)


## An effect making its owner immune to everything from a source it names.
##
## Immune to nothing in particular: the query is what makes it an immunity, and
## what it refuses is not what this is about.
func _granting_immunity() -> GameplayEffect:
	var nothing: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = EffectFactory.infinite(nothing)

	var immunity: GameplayEffectImmunityComponent = GameplayEffectImmunityComponent.new()
	immunity.incoming_effect_query = GameplayEffectQuery.new()
	effect.components.append(immunity)
	return effect


#region The tag change
## A tag moving reevaluates what its family is about, and nothing else.
func test_a_tag_change_reevaluates_only_what_depends_on_it() -> void:
	var watching: GameplayEffect = _requiring(BURNING)
	var watching_family: GameplayEffect = _requiring(FAMILY)
	var watching_elsewhere: GameplayEffect = _requiring(ELSEWHERE)
	asc.apply_gameplay_effect(watching, asc, 1.0)
	asc.apply_gameplay_effect(watching_family, asc, 1.0)
	asc.apply_gameplay_effect(watching_elsewhere, asc, 1.0)
	_crowd(CROWD)

	asc.effects.index.forget_counters()
	asc.tags.add(BURNING)
	asc.emit_tag_change(BURNING, GameplayTagRuntime.Change.ADDED, 1)

	assert_eq(
		asc.effects.index.inhibition_effects_reevaluated, 2,
		"the one about the tag and the one about its family, and none of the crowd"
	)


## What the tag change decided is what a full pass would have decided.
##
## The scoped pass is only sound if the effects it skips could not have changed
## their answer, so the state afterwards is compared with the state a pass over
## everything produces.
func test_the_scoped_pass_leaves_the_same_state_as_a_full_one() -> void:
	var watching: GameplayEffect = _requiring(BURNING)
	var watching_family: GameplayEffect = _requiring(FAMILY)
	var scoped: ActiveGameplayEffect = asc.apply_gameplay_effect(watching, asc, 1.0)
	var family: ActiveGameplayEffect = asc.apply_gameplay_effect(watching_family, asc, 1.0)

	assert_true(scoped.inhibited, "neither is in force before the tag arrives")
	assert_true(family.inhibited, "including the one about the family")

	asc.tags.add(BURNING)
	asc.emit_tag_change(BURNING, GameplayTagRuntime.Change.ADDED, 1)
	assert_false(scoped.inhibited, "the scoped pass let the one about the tag in")
	assert_false(family.inhibited, "and the one about its family")

	# And a full pass over the same state agrees, which is what "the index
	# changed no answer" means.
	asc.effects.on_owner_tags_changed()
	assert_false(scoped.inhibited, "a full pass leaves it exactly where it was")
	assert_false(family.inhibited, "and the other one too")


## An effect whose requirements are about nothing is still asked.
##
## A query that is not empty and names no tag cannot be filed under a tag, and
## the small bucket it goes in is walked on every change - which is correct and
## is why the bucket has to stay small.
func test_a_requirement_about_no_tag_is_still_reevaluated() -> void:
	var about_nothing: GameplayEffect = _requiring(&"")
	asc.apply_gameplay_effect(about_nothing, asc, 1.0)
	_crowd(20)

	asc.effects.index.forget_counters()
	asc.tags.add(BURNING)
	asc.emit_tag_change(BURNING, GameplayTagRuntime.Change.ADDED, 1)

	assert_eq(
		asc.effects.index.inhibition_effects_reevaluated, 1,
		"the one nothing could index, and none of the crowd"
	)


## An effect requiring `tag` to stay in force. An empty tag makes a query that
## is not empty and is about nothing, which is the unindexable case.
func _requiring(tag: StringName) -> GameplayEffect:
	var nothing: Array[GameplayEffectModifier] = []
	var effect: GameplayEffect = EffectFactory.infinite(nothing)

	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)
	GameplayTagQueryEdits.add_tag(root, tag)

	var requirement: GameplayEffectTargetTagRequirementsComponent = (
		GameplayEffectTargetTagRequirementsComponent.new()
	)
	requirement.ongoing_query = query
	effect.components.append(requirement)
	return effect
#endregion


#region What the index promises
## Removing an effect takes it out of every bucket it was in.
func test_removal_empties_every_bucket_it_was_in() -> void:
	var stackable: GameplayEffect = _stackable()
	var watching: GameplayEffect = _requiring(BURNING)
	var first: ActiveGameplayEffect = asc.apply_gameplay_effect(stackable, asc, 1.0)
	var second: ActiveGameplayEffect = asc.apply_gameplay_effect(watching, asc, 1.0)

	assert_eq(asc.effects.index.filed_count(), 2, "both are filed")

	asc.remove_active_effect(first)
	asc.remove_active_effect(second)

	assert_eq(asc.effects.index.filed_count(), 0, "and neither is once they are gone")
	assert_eq(
		asc.effects.index.requirement_dependents(BURNING).size(), 0,
		"nothing is left depending on the tag"
	)


## An effect is in a bucket once, however many times it is filed.
func test_an_effect_is_in_a_bucket_once() -> void:
	var stackable: GameplayEffect = _stackable()
	var active: ActiveGameplayEffect = asc.apply_gameplay_effect(stackable, asc, 1.0)

	asc.effects.index.refresh(active)
	asc.effects.index.refresh(active)

	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		stackable, GameplayEffectContext.new(fixture.owner), 1.0
	)
	spec.source_asc = asc
	assert_eq(
		asc.effects.index.stack_candidates(spec).size(), 1,
		"refiling does not put it in twice"
	)


## Taking everything off leaves the index empty as well as the list.
func test_cleaning_up_empties_the_index_as_well_as_the_list() -> void:
	_crowd(20)
	asc.apply_gameplay_effect(_requiring(BURNING), asc, 1.0)
	assert_gt(asc.effects.index.filed_count(), 20, "there is something to clear")

	asc.effects.cleanup()

	assert_eq(asc.effects.active_count(), 0, "the list is empty")
	assert_eq(asc.effects.index.filed_count(), 0, "and so is the index")
	assert_eq(
		asc.effects.index.requirement_dependents(BURNING).size(), 0,
		"with nothing left in any bucket"
	)
#endregion
