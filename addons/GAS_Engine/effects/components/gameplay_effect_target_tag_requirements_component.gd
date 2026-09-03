## Replaces GameplayEffect.application_required_tags/application_ignore_tags:
## the target must satisfy `application_query` for the application to proceed.
##
## An empty query (no root expression) matches everything - the same "no
## restriction" an effect authored with neither list had under F2.
## `ongoing_query`/`removal_query` are read by GameplayEffectRuntime's own
## inhibition/removal reevaluation, not by any hook here - see
## GameplayEffectInhibitionRuntime.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectTargetTagRequirementsComponent extends GameplayEffectComponent

@export var application_query: GameplayTagQuery = null

## While true, the active effect is uninhibited; while false, its
## contributions/tags stay registered but detached. Null never inhibits.
@export var ongoing_query: GameplayTagQuery = null

## When true, the active effect is removed outright - and, checked here at
## application time too, a matching removal_query refuses the application
## before it ever starts.
@export var removal_query: GameplayTagQuery = null


func can_apply(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	if request.target_asc == null:
		if _is_restrictive():
			return GameplayEffectComponentDecision.deny("no target to evaluate the tag requirement against")
		return GameplayEffectComponentDecision.allow()
	if removal_query != null and not removal_query.is_empty() and removal_query.matches_runtime(request.target_asc.tags):
		return GameplayEffectComponentDecision.deny("target already satisfies this effect's own removal query")
	if application_query == null or application_query.is_empty():
		return GameplayEffectComponentDecision.allow()
	if application_query.matches_runtime(request.target_asc.tags):
		return GameplayEffectComponentDecision.allow()
	return GameplayEffectComponentDecision.deny("target does not satisfy the application tag query")


func _is_restrictive() -> bool:
	return (
		(application_query != null and not application_query.is_empty())
		or (removal_query != null and not removal_query.is_empty())
	)
