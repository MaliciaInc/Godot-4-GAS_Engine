## A random chance this application proceeds at all - 0.0 always refuses,
## 1.0 always allows, and anything between draws exactly one sample from the
## request's shared RNG so a test can seed it and get a deterministic answer.
##
## An AoE resolves this independently per target: each target's application
## builds its own request, so each carries its own draw.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectChanceToApplyComponent extends GameplayEffectComponent

@export_range(0.0, 1.0) var chance: float = 1.0


func can_apply(request: GameplayEffectComponentApplyRequest) -> GameplayEffectComponentDecision:
	if chance >= 1.0:
		return GameplayEffectComponentDecision.allow()
	if chance <= 0.0:
		return GameplayEffectComponentDecision.deny("chance is zero")
	var rng: RandomNumberGenerator = request.rng if request.rng != null else RandomNumberGenerator.new()
	if rng.randf() < chance:
		return GameplayEffectComponentDecision.allow()
	return GameplayEffectComponentDecision.deny("chance roll failed")
