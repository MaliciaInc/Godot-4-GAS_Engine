## The one physics hit a context payload commonly needs - space kind,
## position, normal, collider - composing GameplayTargetHit rather than
## redeclaring its fields a second time.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayHitContextPayload extends GameplayEffectContextPayload

## Immutable once populated by whoever builds this payload, exactly like a
## GameplayAbilityTargetData entry - shared by reference on copy, never
## re-derived.
var hit: GameplayTargetHit = null


func create_application_copy() -> GameplayEffectContextPayload:
	var copy: GameplayHitContextPayload = GameplayHitContextPayload.new()
	copy.hit = hit
	return copy
