## Which item prototypes grant what.
##
## The lookup table between an inventory and an ability system. Kept as a
## resource so loot design is authored rather than coded, and so a project can
## carry several catalogues for several kinds of wearer.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GlootGasEquipmentCatalog extends Resource

@export var grants: Array[GlootGasEquipmentGrant] = []


func find(prototype_id: StringName) -> GlootGasEquipmentGrant:
	for grant: GlootGasEquipmentGrant in grants:
		if grant != null and grant.prototype_id == prototype_id:
			return grant
	return null


## Whether this catalogue can be trusted to answer at all.
##
## Two entries for one prototype id make every lookup ambiguous. Resolving that
## by letting the last one win would answer confidently with whichever entry
## happened to be further down the file, and the wrong sword would be silently
## stronger. An ambiguous catalogue is refused instead, at bind time, where
## somebody is still looking.
func is_valid() -> bool:
	var seen: Array[StringName] = []
	for grant: GlootGasEquipmentGrant in grants:
		if grant == null or String(grant.prototype_id).is_empty():
			return false
		if seen.has(grant.prototype_id):
			return false
		seen.append(grant.prototype_id)
	return true
