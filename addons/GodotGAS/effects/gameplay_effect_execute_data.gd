## One base mutation an effect is executing, threaded through the pre/post
## execute hooks around it.
##
## Distinct from AttributeBaseMutation: that one is the runtime's own staged
## write, opaque to gameplay code. This is the gameplay-facing view of the
## same write, with the effect/handle/ASC context a hook needs to react.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectExecuteData extends RefCounted

var spec: GameplayEffectSpec = null
var effect_handle: GameplayEffectHandle = null
var source_asc: AbilitySystemComponent = null
var target_asc: AbilitySystemComponent = null
var attribute_name: StringName = &""

var old_base: float = 0.0
var requested_base: float = 0.0
var proposed_base: float = 0.0
var committed_base: float = 0.0


## The only sanctioned way for a pre hook to change what gets clamped and
## committed - rejects a non-finite value rather than staging one that would
## just fail the finite check one step later with a less specific cause.
func set_proposed_base(value: float) -> bool:
	if not is_finite(value):
		return false
	proposed_base = value
	return true
