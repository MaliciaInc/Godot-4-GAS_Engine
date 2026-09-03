## Grants immunity while the effect carrying this component is active on the
## target: any incoming application `incoming_effect_query` matches is
## refused before anything observable happens.
##
## Purely declarative - matching against an incoming spec is not a generic
## component hook, and runs in GameplayEffectRuntime's own pre-preflight
## stage, before the incoming effect's own components are even asked.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayEffectImmunityComponent extends GameplayEffectComponent

@export var incoming_effect_query: GameplayEffectQuery = null
