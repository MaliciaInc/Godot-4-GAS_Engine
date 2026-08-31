## Tags granted to the target for as long as this effect is active. Replaces
## GameplayEffect.granted_tags as the authoring surface; the runtime still
## grants and revokes through the same tag registry it always did, reading
## these from GameplayEffectSpec.get_granted_tags() instead of a bare field.
##
## Instant effects grant no tags in any case - they leave nothing behind to
## hold one.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectTargetTagsComponent extends GameplayEffectComponent

@export var granted_tags: Array[StringName] = []
