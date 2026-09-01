## The result of instantiating and validating an ability scene, held open for
## exactly one transactional operation: commit it into a real grant, or
## discard it and free what it instantiated.
##
## Never held across frames. A prepared grant is built and resolved - one way
## or the other - inside the single call that created it; nothing in this
## addon keeps one waiting for a future decision.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name PreparedAbilityGrant extends RefCounted

var validation: AbilityGrantValidationResult = AbilityGrantValidationResult.new()

## The scene's own root instance, still unparented. Null when validation
## failed before instantiation produced anything to hold.
var probe: GameplayAbility = null

var definition: GameplayAbilityDefinitionSnapshot = null
var level: float = 1.0
var input_id: int = -1
var source: GameplayAbilitySource = null

## True once commit_prepared_grant or discard_prepared_grant has resolved
## this. Guards against consuming - or double-freeing - the same
## preparation twice.
var consumed: bool = false
