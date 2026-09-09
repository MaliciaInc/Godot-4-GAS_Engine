## Everything a GameplayMagnitude needs to resolve itself: which spec it
## belongs to, the source and target it may capture from, and the level its
## own scaling runs at.
##
## Bundled the same way GameplayEffectEvaluator.Request is, and for the same
## reason: one typed value instead of four loose parameters every resolve()
## override would otherwise repeat.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayMagnitudeContext extends RefCounted

var spec: GameplayEffectSpec = null
var source_asc: AbilitySystemComponent = null
var target_asc: AbilitySystemComponent = null
var level: float = 1.0


## The ordinary context: a spec, the two sides, and the spec's own level.
##
## The level is not a parameter because there has never been a caller that
## wanted a different one - a magnitude scales at the level the application
## is at, and a context saying otherwise would be a magnitude resolved for
## an application that is not happening.
static func of(
	for_spec: GameplayEffectSpec,
	from_source: AbilitySystemComponent,
	on_target: AbilitySystemComponent
) -> GameplayMagnitudeContext:
	var made: GameplayMagnitudeContext = GameplayMagnitudeContext.new()
	made.spec = for_spec
	made.source_asc = from_source
	made.target_asc = on_target
	made.level = for_spec.level if for_spec != null else 1.0
	return made
