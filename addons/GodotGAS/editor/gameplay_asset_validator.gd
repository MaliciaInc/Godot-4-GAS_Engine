## Reusable asset validation, over the seven kinds the editor authors.
##
## Never a second validation authority: every check here calls the runtime's
## own validate()/validate_definition(), which is what actually gates
## gameplay, and only translates the result into GameplayAssetValidationResult.
## The one exception is structural authoring checks nothing else performs
## because they need no live ASC to answer - a cost missing its amount, a
## component definition GameplayEffectComponent.validate_definition() itself
## already covers, a query naming an empty/cyclic GameplayTagQuery.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayAssetValidator extends RefCounted

const Result = preload("res://addons/GodotGAS/editor/gameplay_asset_validation_result.gd")


#region GameplayEffect
static func validate_effect(effect: GameplayEffect) -> Array[Result]:
	var findings: Array[Result] = []
	if effect == null:
		findings.append(Result.error(null, "", Result.Code.MISSING_REFERENCE))
		return findings

	for index: int in effect.components.size():
		var component: GameplayEffectComponent = effect.components[index]
		if component == null:
			continue
		var outcome: GameplayEffectComponentValidationResult = component.validate_definition(effect)
		if not outcome.is_ok():
			findings.append(Result.error(effect, "components[%d]" % index, Result.Code.INVALID_COMPONENT_DEFINITION))

	for index: int in effect.modifiers.size():
		var modifier: GameplayEffectModifier = effect.modifiers[index]
		if modifier != null:
			findings.append_array(validate_magnitude(modifier.magnitude, effect, "modifiers[%d].magnitude" % index))
	return findings
#endregion


#region Ability scene
static func validate_ability_scene(scene: PackedScene) -> Array[Result]:
	var findings: Array[Result] = []
	if scene == null:
		findings.append(Result.error(null, "", Result.Code.SCENE_MISSING))
		return findings

	var instance: Node = scene.instantiate()
	if instance == null:
		findings.append(Result.error(scene, "", Result.Code.SCENE_MISSING))
		return findings

	var ability: GameplayAbility = instance as GameplayAbility
	if ability == null:
		findings.append(Result.error(scene, "", Result.Code.ROOT_NOT_GAMEPLAY_ABILITY))
	else:
		findings.append_array(validate_costs(ability.costs, scene))
		if ability.activation_required_query != null:
			findings.append_array(validate_tag_query(ability.activation_required_query, scene, "activation_required_query"))
		if ability.activation_blocked_query != null:
			findings.append_array(validate_tag_query(ability.activation_blocked_query, scene, "activation_blocked_query"))
	instance.free()
	return findings
#endregion


#region GameplayTagQuery
static func validate_tag_query(
	query: GameplayTagQuery, asset: Object = null, field: String = ""
) -> Array[Result]:
	var findings: Array[Result] = []
	if query == null:
		return findings
	var outcome: GameplayTagQueryValidationResult = query.validate()
	match outcome.status:
		GameplayTagQueryValidationResult.Status.CYCLIC_EXPRESSION:
			findings.append(Result.error(asset if asset != null else query, field, Result.Code.CYCLIC_TAG_QUERY))
		GameplayTagQueryValidationResult.Status.EMPTY_TAG:
			findings.append(Result.error(asset if asset != null else query, field, Result.Code.EMPTY_TAG_IN_QUERY))
		GameplayTagQueryValidationResult.Status.INVALID_TAG:
			findings.append(Result.error(asset if asset != null else query, field, Result.Code.INVALID_TAG_IN_QUERY))
	return findings
#endregion


#region GameplayEffectQuery
static func validate_effect_query(query: GameplayEffectQuery) -> Array[Result]:
	var findings: Array[Result] = []
	if query == null:
		return findings
	findings.append_array(validate_tag_query(query.asset_tags, query, "asset_tags"))
	findings.append_array(validate_tag_query(query.granted_tags, query, "granted_tags"))
	findings.append_array(validate_tag_query(query.source_tags, query, "source_tags"))
	findings.append_array(validate_tag_query(query.target_tags, query, "target_tags"))
	return findings
#endregion


#region Costs
## Structural authoring checks only - whether a percentage lands 0-100% needs
## a live attribute to resolve against, and GameplayAbilityCostResolver
## already answers that (PERCENT_OUT_OF_RANGE/NON_FINITE_VALUE) at the one
## place a cost is ever actually resolved.
static func validate_costs(costs: Array[GameplayAbilityCost], asset: Object = null) -> Array[Result]:
	var findings: Array[Result] = []
	for index: int in costs.size():
		var cost: GameplayAbilityCost = costs[index]
		if cost == null:
			continue
		var target: Object = asset if asset != null else cost
		if cost.amount == null:
			findings.append(Result.error(target, "costs[%d].amount" % index, Result.Code.MISSING_COST_AMOUNT))
		if cost.target_attribute == &"":
			findings.append(Result.error(target, "costs[%d].target_attribute" % index, Result.Code.MISSING_COST_TARGET_ATTRIBUTE))
		var needs_reference: bool = (
			cost.mode == GameplayAbilityCost.Mode.PERCENT_OF_BASE
			or cost.mode == GameplayAbilityCost.Mode.PERCENT_OF_CURRENT
		)
		if needs_reference and cost.reference_attribute == &"":
			findings.append(
				Result.error(target, "costs[%d].reference_attribute" % index, Result.Code.MISSING_COST_REFERENCE_ATTRIBUTE)
			)
	return findings
#endregion


#region Components
static func validate_components(components: Array[GameplayEffectComponent], effect: GameplayEffect) -> Array[Result]:
	var findings: Array[Result] = []
	for index: int in components.size():
		var component: GameplayEffectComponent = components[index]
		if component == null:
			continue
		var outcome: GameplayEffectComponentValidationResult = component.validate_definition(effect)
		if not outcome.is_ok():
			var reported_asset: Object = effect if effect != null else component
			findings.append(Result.error(reported_asset, "components[%d]" % index, Result.Code.INVALID_COMPONENT_DEFINITION))
	return findings
#endregion


#region Magnitudes
static func validate_magnitude(
	magnitude: GameplayMagnitude, asset: Object = null, field: String = ""
) -> Array[Result]:
	var findings: Array[Result] = []
	if magnitude == null:
		findings.append(Result.error(asset, field, Result.Code.MISSING_MAGNITUDE))
	return findings
#endregion
