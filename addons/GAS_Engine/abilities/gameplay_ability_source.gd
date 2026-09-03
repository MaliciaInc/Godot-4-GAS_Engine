## Who or what caused an ability to be granted, without assuming it is a Node.
##
## Upstream used `Node`/`Object`/`Variant` as a universal source, so every
## consumer had to guess what a source actually was before it could ask
## anything about it. A grant from a piece of equipment, a quest, or a
## designer-authored default all name a source that is not necessarily a
## scene-tree Node at all.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@abstract
class_name GameplayAbilitySource extends RefCounted


## A diagnostic label only. Gameplay identity never depends on this string.
func source_id() -> StringName:
	return &""
