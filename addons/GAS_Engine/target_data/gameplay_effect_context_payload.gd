## Typed, opaque metadata a game attaches to a GameplayEffectContext.
##
## Weapon data, hit classification, crit info, attack id, surface info, team
## data, combo data - GAS_Engine does not invent any of those schemas. A
## game subclasses this once per kind of metadata it needs, and
## GameplayEffectContext carries the array without knowing what is in it.
##
## The lookup boundary is by Script, not by a string key or an enum: that is
## a GDScript reflection limitation, not a design choice, and it is still
## typed - never a Dictionary domain payload.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
@abstract
class_name GameplayEffectContextPayload extends RefCounted


## A deep semantic copy for one more target's application copy of the
## context that holds this payload. Never `duplicate()`: a payload wrapping
## a live Node reference or an opaque handle must decide for itself what
## "the same logical thing, for a different target" means. Null means this
## payload cannot be copied - GameplayEffectContext.create_application_copy()
## fails explicitly rather than handing out a context missing the metadata
## silently.
func create_application_copy() -> GameplayEffectContextPayload:
	push_error(
		"GAS_Engine: create_application_copy() called on the base "
		+ "GameplayEffectContextPayload. Override it in your specific payload script."
	)
	return null
