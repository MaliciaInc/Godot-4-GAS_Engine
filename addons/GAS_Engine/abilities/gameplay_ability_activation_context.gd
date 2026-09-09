## Why an ability was activated, kept whole.
##
## An event-triggered ability used to be handed only the effect context the
## event carried, so everything else the event knew - which tag fired it, the
## magnitude it came with, who it was aimed at - was gone by the time the
## ability ran. An ability that needed any of it had to reconstruct it from the
## world, which is guessing: the world has moved on since.
##
## So the event travels with the activation. An ability activated by a call
## still gets an effect context and no event, which is what a call means.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayAbilityActivationContext extends RefCounted

var effect_context: GameplayEffectContext = null
var gameplay_event: GameplayEventData = null

static func from_effect_context(context: GameplayEffectContext) -> GameplayAbilityActivationContext:
	var result: GameplayAbilityActivationContext = GameplayAbilityActivationContext.new()
	result.effect_context = context
	return result

static func from_gameplay_event(event: GameplayEventData) -> GameplayAbilityActivationContext:
	var result: GameplayAbilityActivationContext = GameplayAbilityActivationContext.new()
	result.gameplay_event = event
	result.effect_context = event.context if event != null else null
	return result
