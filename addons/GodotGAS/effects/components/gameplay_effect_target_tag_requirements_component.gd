## Replaces GameplayEffect.application_required_tags/application_ignore_tags:
## the target must satisfy this query for the application to proceed.
##
## An empty query (no root expression) matches everything - the same "no
## restriction" an effect authored with neither list had under F2. Task 11
## extends this component with ongoing/removal queries; this task covers
## application only.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectTargetTagRequirementsComponent extends GameplayEffectComponent

@export var application_query: GameplayTagQuery = null


func can_apply(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	if application_query == null or application_query.is_empty():
		return GameplayEffectComponentDecision.allow()
	if request.target_asc == null:
		return GameplayEffectComponentDecision.deny("no target to evaluate the tag requirement against")
	if application_query.matches_runtime(request.target_asc.tags):
		return GameplayEffectComponentDecision.allow()
	return GameplayEffectComponentDecision.deny("target does not satisfy the application tag query")
