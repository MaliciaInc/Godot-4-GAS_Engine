## Declares other GameplayEffects to apply, to the same target, at declared
## lifecycle points - without an ad hoc script watching signals.
##
## Purely declarative, like GameplayEffectRemoveOtherEffectsComponent and
## GameplayEffectImmunityComponent before it: the actual chaining is not a
## generic component hook, it runs from GameplayEffectRuntime itself, at the
## one place each lifecycle point is already decided. Never duplicates
## overflow_effects (Task 12) - that stays the sole overflow owner.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectAdditionalEffectsComponent extends GameplayEffectComponent

## After this effect's own application has committed.
@export var on_application: Array[GameplayEffectConditionalEffect] = []

## After removal whose reason is NATURAL_EXPIRATION.
@export var on_natural_expiration: Array[GameplayEffectConditionalEffect] = []

## After removal for any other gameplay reason (not ASC_CLEANUP).
@export var on_premature_removal: Array[GameplayEffectConditionalEffect] = []

## After any gameplay removal, natural or premature (not ASC_CLEANUP).
@export var on_any_removal: Array[GameplayEffectConditionalEffect] = []
