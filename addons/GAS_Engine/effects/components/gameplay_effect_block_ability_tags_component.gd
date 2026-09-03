## While this effect is active on the target AND uninhibited, blocks any
## ability activation whose effective tags match `query`.
##
## Purely declarative, like GameplayEffectImmunityComponent: read directly by
## AbilityRuntime.activation_error(), never a generic component hook. An
## inhibited owner (Task 11) stops blocking - its own contributions/tags are
## detached too, and this is the same "the effect is not currently in force"
## rule GameplayEffectImmunityComponent already follows.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectBlockAbilityTagsComponent extends GameplayEffectComponent

@export var query: GameplayTagQuery = null
