## GameplayEffectGrantAbilitiesComponent's own prepared state: one entry per
## grant, in the same order as GameplayEffectGrantAbilitiesComponent.grants.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayEffectGrantAbilitiesState extends GameplayEffectComponentState

var prepared_grants: Array[PreparedAbilityGrant] = []
var sources: Array[GameplayAbilityEffectSource] = []
var policies: Array[GameplayEffectAbilityGrant.RemovalPolicy] = []

## True once on_effect_applied has committed these preparations - a stack
## reapplication that reuses this same state (see
## GameplayEffectComponentApplyRequest.existing_active_effect) must not
## commit an already-consumed PreparedAbilityGrant a second time.
var committed: bool = false
