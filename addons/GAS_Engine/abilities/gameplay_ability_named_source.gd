## A grant caused by something that is not a Node - a GLoot prototype id, a
## quest id, or any other identity a bridge already tracks its own way.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT
class_name GameplayAbilityNamedSource extends GameplayAbilitySource

var id: StringName = &""


func source_id() -> StringName:
	return id
