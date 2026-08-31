## Base for a custom, arbitrary application requirement.
##
## The escape hatch for a can-apply question none of the other components
## express - a Resource, not a Callable, so the requirement is an asset a
## designer can author and reuse rather than code wired at one call site.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
@abstract
class_name GameplayEffectApplicationRequirement extends Resource


func can_apply(_request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	push_error(
		"GodotGAS: can_apply() called on the base GameplayEffectApplicationRequirement. "
		+ "Override it in the subclass that authors this requirement."
	)
	return GameplayEffectComponentDecision.deny("unimplemented requirement")
