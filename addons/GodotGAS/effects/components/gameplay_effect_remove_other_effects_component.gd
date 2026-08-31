## Replaces GameplayEffect.remove_effects_with_tags: on a successful
## application, purge every active effect this query matches.
##
## Purely declarative - the removal itself is not a generic component hook.
## It runs in GameplayEffectRuntime's own pre-application stage, reusing the
## same reversible transaction Task 2 introduced: the purge stays undone if
## the incoming application's own outcome ends up refused.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectRemoveOtherEffectsComponent extends GameplayEffectComponent

@export var query: GameplayEffectQuery = null
