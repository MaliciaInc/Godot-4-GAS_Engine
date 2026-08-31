## One ability a GameplayEffectGrantAbilitiesComponent grants while its effect
## is active.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectAbilityGrant extends Resource

## What happens to the granted spec when the granting effect is removed.
enum RemovalPolicy {
	CANCEL_AND_REMOVE_ON_EFFECT_END,  # Cancel a running activation and retire immediately.
	REMOVE_ON_ACTIVE_END,             # No new activations; retire once none is running.
	KEEP_AFTER_EFFECT_END,            # Never retired by this effect ending.
}

@export var ability_scene: PackedScene = null

## Resolved against the granting spec's level. Null defaults to that level
## unscaled.
@export var level: GameplayScalableFloat = null

@export var input_id: int = -1
@export var removal_policy: RemovalPolicy = RemovalPolicy.CANCEL_AND_REMOVE_ON_EFFECT_END
