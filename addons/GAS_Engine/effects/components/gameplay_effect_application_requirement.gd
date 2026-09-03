## Base for a custom, arbitrary application requirement.
##
## The escape hatch for a can-apply question none of the other components
## express - a Resource, not a Callable, so the requirement is an asset a
## designer can author and reuse rather than code wired at one call site.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@abstract
class_name GameplayEffectApplicationRequirement extends Resource


func can_apply(_request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	push_error(
		"GAS_Engine: can_apply() called on the base GameplayEffectApplicationRequirement. "
		+ "Override it in the subclass that authors this requirement."
	)
	return GameplayEffectComponentDecision.deny("unimplemented requirement")
