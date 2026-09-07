## The contracts themselves: what the reference does, case by case.
##
## One file rather than one file per case, because a case is eleven fields and
## twenty files of eleven fields each is twenty places for the shape to drift.
## What matters is that every case says all eleven things, and the runner
## refuses one that does not.
##
## Every case is stamped with the reference version it was taken from. No Unreal
## process is run: the expectations are authored from the reference's documented
## behaviour, which is what makes them reviewable - a wrong expectation is a
## wrong sentence in this file, rather than an invisible disagreement with a
## binary nobody has.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayParityContracts extends RefCounted

const EffectFactory = preload("res://test/fixtures/test_effect_factory.gd")

const HEALTH: StringName = &"health"
const ATTACK: StringName = &"attack"
const BURNING: StringName = &"Status.Burning"
const STUNNED: StringName = &"State.Stunned"

const AT_PATH: String = "res://test_only/parity_%d.tres"


static func all() -> Array[GameplayParityCase]:
	return [
		_an_instant_effect_changes_the_base_and_leaves_nothing_running(),
		_a_duration_effect_composes_without_touching_the_base(),
		_two_of_a_stacking_effect_are_one_application(),
		_a_granting_effect_holds_its_tag_for_as_long_as_it_runs(),
		_an_effect_removed_gives_back_everything_it_contributed(),
		_a_multiplying_modifier_composes_after_the_additive_ones(),
	]


#region The cases
## An instant effect is arithmetic on the base value and nothing afterwards.
##
## The reference's INSTANT is not a short duration: it changes the number and
## leaves, so there is nothing to address, nothing to remove and nothing to tick.
static func _an_instant_effect_changes_the_base_and_leaves_nothing_running() -> GameplayParityCase:
	var case: GameplayParityCase = _case(&"instant.changes_the_base")
	case.attributes = {HEALTH: 100.0}
	case.input = func(fixture: ASCFixture) -> void:
		EffectFactory.apply(
			fixture.asc,
			_named(EffectFactory.instant([EffectFactory.add(HEALTH, -30.0)] as Array[GameplayEffectModifier]))
		)
	case.expected_attributes = {HEALTH: 70.0}
	case.expected_effects = 0
	# The attribute change and nothing else. Whether the reference announces an
	# instant application through an "executed" event as well is not something
	# this corpus can settle from documentation, so it does not claim it - a
	# corpus that guessed would be asserting its own guess.
	case.expected_signals = [&"attribute_changed"] as Array[StringName]
	case.expected_identity = &"no_handles"
	case.expected_authoring = &"apply_gameplay_effect"
	return case


## A duration effect contributes to the current value and leaves the base alone.
##
## Which is the distinction the whole aggregation model rests on: the base is
## what a character is, and the current value is what it is right now.
static func _a_duration_effect_composes_without_touching_the_base() -> GameplayParityCase:
	var case: GameplayParityCase = _case(&"duration.composes_over_the_base")
	case.attributes = {ATTACK: 10.0}
	case.input = func(fixture: ASCFixture) -> void:
		EffectFactory.apply(
			fixture.asc,
			_named(
				EffectFactory.duration(
					[EffectFactory.add(ATTACK, 5.0)] as Array[GameplayEffectModifier], 30.0
				)
			)
		)
	case.expected_attributes = {ATTACK: 15.0}
	case.expected_effects = 1
	case.expected_signals = [&"active_effect_added", &"attribute_changed"] as Array[StringName]
	case.expected_order = [&"active_effect_added"] as Array[StringName]
	case.expected_identity = &"one_handle_per_application"
	case.expected_authoring = &"apply_gameplay_effect"
	return case


## Two of a stacking effect are one application with a count on it.
##
## The reference stacks by aggregating onto the application that is already
## there, which is why a stack is announced as a change and not as an arrival:
## a second handle would be a second thing to remove.
static func _two_of_a_stacking_effect_are_one_application() -> GameplayParityCase:
	var case: GameplayParityCase = _case(&"stacking.two_are_one_application")
	case.attributes = {ATTACK: 10.0}
	case.input = func(fixture: ASCFixture) -> void:
		var stacking: GameplayEffect = _named(
			EffectFactory.stacked(
				EffectFactory.infinite(
					[EffectFactory.add(ATTACK, 2.0)] as Array[GameplayEffectModifier]
				),
				GameplayEffect.StackingType.AGGREGATE_BY_TARGET,
				3
			)
		)
		# The reference scales a stacking effect's modifier by how many of it
		# there are. GAS_Engine offers that and does not default to it - see the
		# matrix, where the default is an explicit deviation rather than a gap.
		stacking.factor_in_stack_count = true
		EffectFactory.apply(fixture.asc, stacking)
		EffectFactory.apply(fixture.asc, stacking)
	case.expected_attributes = {ATTACK: 14.0}
	case.expected_effects = 1
	case.expected_signals = [&"active_effect_stack_changed"] as Array[StringName]
	case.expected_order = [&"active_effect_added", &"active_effect_stack_changed"] as Array[StringName]
	case.expected_identity = &"stacking_keeps_one_handle"
	case.expected_authoring = &"apply_gameplay_effect"
	return case


## A granting effect holds its tag while it runs, by reference count.
static func _a_granting_effect_holds_its_tag_for_as_long_as_it_runs() -> GameplayParityCase:
	var case: GameplayParityCase = _case(&"tags.granted_while_running")
	case.attributes = {HEALTH: 100.0}
	case.tags = [BURNING] as Array[StringName]
	case.input = func(fixture: ASCFixture) -> void:
		EffectFactory.apply(
			fixture.asc,
			_named(
				EffectFactory.granting(
					EffectFactory.infinite([] as Array[GameplayEffectModifier]),
					[STUNNED] as Array[StringName]
				)
			)
		)
	case.expected_attributes = {HEALTH: 100.0}
	case.expected_tags = {BURNING: 1, STUNNED: 1}
	case.expected_effects = 1
	case.expected_signals = [&"tag_added"] as Array[StringName]
	case.expected_identity = &"one_handle_per_application"
	case.expected_authoring = &"apply_gameplay_effect"
	return case


## Removing an effect gives back everything it contributed, and says so.
static func _an_effect_removed_gives_back_everything_it_contributed() -> GameplayParityCase:
	var case: GameplayParityCase = _case(&"removal.gives_everything_back")
	case.attributes = {ATTACK: 10.0}
	case.input = func(fixture: ASCFixture) -> void:
		var applied: ActiveGameplayEffect = EffectFactory.apply(
			fixture.asc,
			_named(
				EffectFactory.granting(
					EffectFactory.infinite(
						[EffectFactory.add(ATTACK, 7.0)] as Array[GameplayEffectModifier]
					),
					[STUNNED] as Array[StringName]
				)
			)
		)
		fixture.asc.effects.remove(applied)
	case.expected_attributes = {ATTACK: 10.0}
	case.expected_tags = {STUNNED: 0}
	case.expected_effects = 0
	case.expected_signals = [&"active_effect_removed", &"tag_removed"] as Array[StringName]
	case.expected_order = [&"active_effect_added", &"active_effect_removed"] as Array[StringName]
	case.expected_identity = &"no_handles"
	case.expected_authoring = &"remove_active_effects"
	return case


## Multiply composes after the additive contributions, not alongside them.
##
## `(base + additive) * multiplier`, which is the reference's channel order and
## the reason a +5 and a x2 on a 10 give 30 rather than 25.
static func _a_multiplying_modifier_composes_after_the_additive_ones() -> GameplayParityCase:
	var case: GameplayParityCase = _case(&"aggregation.multiply_after_add")
	case.attributes = {ATTACK: 10.0}
	case.input = func(fixture: ASCFixture) -> void:
		EffectFactory.apply(
			fixture.asc,
			_named(
				EffectFactory.infinite(
					[EffectFactory.add(ATTACK, 5.0)] as Array[GameplayEffectModifier]
				)
			)
		)
		EffectFactory.apply(
			fixture.asc,
			_named(
				EffectFactory.infinite(
					[EffectFactory.multiply(ATTACK, 2.0)] as Array[GameplayEffectModifier]
				)
			)
		)
	case.expected_attributes = {ATTACK: 30.0}
	case.expected_effects = 2
	case.expected_signals = [&"attribute_changed"] as Array[StringName]
	case.expected_identity = &"one_handle_per_application"
	case.expected_authoring = &"apply_gameplay_effect"
	return case
#endregion


#region Getting there
static func _case(id: StringName) -> GameplayParityCase:
	var case: GameplayParityCase = GameplayParityCase.new()
	case.id = id
	return case


## An effect that lives somewhere, so two runs of the corpus name it the same.
static func _named(effect: GameplayEffect) -> GameplayEffect:
	_made += 1
	effect.take_over_path(AT_PATH % _made)
	return effect


static var _made: int = 0
#endregion
