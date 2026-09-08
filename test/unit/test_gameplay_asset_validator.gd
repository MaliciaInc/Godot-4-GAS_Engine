## GameplayAssetValidator: a reader over each asset kind's own validation,
## never a second authority. These tests prove the wrapping is faithful, not
## that GameplayTagQuery.validate()/GameplayEffectComponent.validate_definition()
## are themselves correct - those already have their own suites.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Validator = preload("res://addons/GAS_Engine/editor/gameplay_asset_validator.gd")
const Result = preload("res://addons/GAS_Engine/editor/gameplay_asset_validation_result.gd")

const ATTACK: StringName = TestAttributeSet.ATTACK


#region GameplayEffect
func test_a_clean_effect_has_no_findings() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.add(ATTACK, 1.0)])
	assert_true(Validator.validate_effect(effect).is_empty())


func test_null_effect_is_a_missing_reference() -> void:
	var findings: Array[Result] = Validator.validate_effect(null)
	assert_eq(findings.size(), 1)
	assert_eq(findings[0].code, Result.Code.MISSING_REFERENCE)


func test_a_missing_magnitude_is_reported() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.add(ATTACK, 1.0)])
	effect.modifiers[0].magnitude = null
	var findings: Array[Result] = Validator.validate_effect(effect)
	assert_eq(findings.size(), 1)
	assert_eq(findings[0].code, Result.Code.MISSING_MAGNITUDE)
	assert_eq(findings[0].field, "modifiers[0].magnitude")
#endregion


#region GameplayTagQuery
func test_a_valid_query_has_no_findings() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	expression.tags = [&"Status.Wet"]
	query.root = expression
	assert_true(Validator.validate_tag_query(query).is_empty())


func test_an_empty_tag_in_a_query_is_reported() -> void:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	expression.tags = [&""]
	query.root = expression
	var findings: Array[Result] = Validator.validate_tag_query(query, null, "field")
	assert_eq(findings.size(), 1)
	assert_eq(findings[0].code, Result.Code.EMPTY_TAG_IN_QUERY)
	assert_eq(findings[0].field, "field")


func test_a_null_query_has_no_findings() -> void:
	assert_true(Validator.validate_tag_query(null).is_empty())
#endregion


#region GameplayEffectQuery
func test_effect_query_checks_all_four_tag_queries() -> void:
	var bad: GameplayTagQuery = GameplayTagQuery.new()
	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ALL
	expression.tags = [&""]
	bad.root = expression

	var query: GameplayEffectQuery = GameplayEffectQuery.new()
	query.asset_tags = bad
	query.target_tags = bad

	var findings: Array[Result] = Validator.validate_effect_query(query)
	assert_eq(findings.size(), 2)
	assert_eq(findings[0].field, "asset_tags")
	assert_eq(findings[1].field, "target_tags")
#endregion


#region Costs
func test_a_clean_absolute_cost_has_no_findings() -> void:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = &"mana"
	cost.amount = Factory.scalable_magnitude(10.0).value
	assert_true(Validator.validate_costs([cost]).is_empty())


func test_a_percentage_cost_missing_its_reference_attribute_is_reported() -> void:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.PERCENT_OF_BASE
	cost.target_attribute = &"mana"
	cost.amount = Factory.scalable_magnitude(0.1).value
	var findings: Array[Result] = Validator.validate_costs([cost])
	assert_eq(findings.size(), 1)
	assert_eq(findings[0].code, Result.Code.MISSING_COST_REFERENCE_ATTRIBUTE)


func test_a_cost_missing_amount_and_target_reports_both() -> void:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	var findings: Array[Result] = Validator.validate_costs([cost])
	var codes: Array[Result.Code] = []
	for finding: Result in findings:
		codes.append(finding.code)
	assert_true(codes.has(Result.Code.MISSING_COST_AMOUNT))
	assert_true(codes.has(Result.Code.MISSING_COST_TARGET_ATTRIBUTE))
#endregion


#region Ability scene
func test_a_valid_ability_scene_has_no_findings() -> void:
	var ability: GameplayAbility = GameplayAbility.new()
	ability.ability_tags = [&"Ability.Valid"]
	var scene: PackedScene = Factory.ability_scene(ability)
	assert_true(Validator.validate_ability_scene(scene).is_empty())


func test_a_null_scene_is_reported_as_missing() -> void:
	var findings: Array[Result] = Validator.validate_ability_scene(null)
	assert_eq(findings.size(), 1)
	assert_eq(findings[0].code, Result.Code.SCENE_MISSING)


func test_an_ability_scene_with_a_bad_cost_surfaces_it() -> void:
	var ability: GameplayAbility = GameplayAbility.new()
	ability.costs = [GameplayAbilityCost.new()]
	var scene: PackedScene = Factory.ability_scene(ability)
	var findings: Array[Result] = Validator.validate_ability_scene(scene)
	assert_true(findings.size() >= 2, "missing amount and missing target attribute, at least")
#endregion


#region Empty slots
## An author clicks Add Element and leaves the row empty. Everything
## downstream steps over it, so the tool that exists to catch what was left
## unfinished is the only one that can say so - and for three of these four
## arrays it stepped over it too.
func test_an_empty_row_in_an_authored_array_is_reported() -> void:
	var effect: GameplayEffect = Factory.instant([Factory.add(ATTACK, 1.0)])
	effect.modifiers.append(null)
	effect.components.append(null)

	var findings: Array[Result] = Validator.validate_effect(effect)

	assert_eq(findings.size(), 2, "the empty modifier row and the empty component row")
	for finding: Result in findings:
		assert_eq(finding.code, Result.Code.MISSING_REFERENCE, finding.field)


func test_an_empty_cost_row_is_reported() -> void:
	# The one that costs the most: an ability whose only cost row is empty is
	# free, and looked clean.
	var findings: Array[Result] = Validator.validate_costs(
		[null] as Array[GameplayAbilityCost]
	)
	assert_eq(findings.size(), 1)
	assert_eq(findings[0].code, Result.Code.MISSING_REFERENCE)
	assert_eq(findings[0].field, "costs[0]", "and says which row")
#endregion
#region What only a profile can answer
## Two questions an effect cannot answer on its own, because the answer depends
## on which arithmetic the entity applying it composes by. Both are warnings:
## each configuration is legal, and only one of them surprises somebody who
## came from the reference.
func _unreal_profile() -> GameplayCompatibilityProfile:
	var profile: GameplayCompatibilityProfile = GameplayCompatibilityProfile.new()
	profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	return profile


func _codes(findings: Array[Result]) -> Array:
	var codes: Array = []
	for finding: Result in findings:
		codes.append(finding.code)
	return codes


func test_a_legacy_multiply_under_the_unreal_profile_is_said_out_loud() -> void:
	var effect: GameplayEffect = Factory.infinite(
		[Factory.multiply(ATTACK, 1.5)] as Array[GameplayEffectModifier]
	)

	assert_false(
		_codes(Validator.validate_effect(effect)).has(
			Result.Code.LEGACY_OPERATION_UNDER_UNREAL_PROFILE
		),
		"with no profile in front of it there is no question to answer"
	)

	var findings: Array[Result] = Validator.validate_effect(effect, _unreal_profile())
	assert_true(
		_codes(findings).has(Result.Code.LEGACY_OPERATION_UNDER_UNREAL_PROFILE),
		"and under the profile that gives the name a second meaning, there is"
	)
	for finding: Result in findings:
		if finding.code == Result.Code.LEGACY_OPERATION_UNDER_UNREAL_PROFILE:
			assert_eq(finding.severity, Result.Severity.WARNING, "it is not an error")


func test_a_stacking_effect_that_never_answered_the_stack_question_is_said_out_loud() -> void:
	var stacking: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 10.0)] as Array[GameplayEffectModifier]),
		GameplayEffect.StackingType.AGGREGATE_BY_SOURCE,
		4,
		false
	)

	assert_true(
		_codes(Validator.validate_effect(stacking, _unreal_profile())).has(
			Result.Code.STACKING_WITHOUT_STACK_COUNT_ANSWER
		),
		"the reference scales by the stack and this engine does not"
	)


func test_answering_the_stack_question_ends_it() -> void:
	var stacking: GameplayEffect = Factory.stacked(
		Factory.infinite([Factory.add(ATTACK, 10.0)] as Array[GameplayEffectModifier]),
		GameplayEffect.StackingType.AGGREGATE_BY_SOURCE,
		4,
		true
	)

	assert_false(
		_codes(Validator.validate_effect(stacking, _unreal_profile())).has(
			Result.Code.STACKING_WITHOUT_STACK_COUNT_ANSWER
		),
		"answered on purpose is not a warning"
	)


## An effect that answered the question, in each of the two ways there are to
## answer it, says nothing under either profile.
##
##     [what it is, the effect, the code it must not carry]
func _quiet_cases() -> Array:
	return [
		[
			"an explicit arm",
			Factory.infinite(
				[
					Factory.modifier(
						ATTACK, GameplayEffectModifier.Operation.MULTIPLY_COMPOUND, 1.5
					)
				] as Array[GameplayEffectModifier]
			),
			Result.Code.LEGACY_OPERATION_UNDER_UNREAL_PROFILE,
		],
		[
			"nothing that stacks",
			Factory.infinite([Factory.add(ATTACK, 10.0)] as Array[GameplayEffectModifier]),
			Result.Code.STACKING_WITHOUT_STACK_COUNT_ANSWER,
		],
	]


func test_an_effect_with_nothing_to_answer_is_left_alone(
	case: Array = use_parameters(_quiet_cases())
) -> void:
	var described: String = case[0]
	var effect: GameplayEffect = case[1]
	var never: Result.Code = case[2]

	assert_false(
		_codes(Validator.validate_effect(effect, _unreal_profile())).has(never),
		"%s: nothing to warn about" % described
	)
#endregion
