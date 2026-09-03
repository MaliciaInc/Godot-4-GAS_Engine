## Exactly what one equipped item put on its wearer.
##
## Taking an item off removes what this says was given, and nothing else. The
## alternative - looking the grant up again and undoing what it *should* have
## given - goes wrong the moment anything has changed in between: a catalogue
## edited while the game ran, an ability the wearer had already lost, a tag some
## other source is also holding. The receipt is what happened; the grant is only
## what was intended.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GlootGasEquipmentReceipt extends RefCounted

var prototype_id: StringName = &""

var granted_abilities: Array[GameplayAbilityHandle] = []
var applied_effects: Array[GameplayEffectHandle] = []

## Recorded one entry per grant, not as a set: the ASC counts tag references, so
## removing exactly as many as were added leaves whatever anyone else added.
var added_tags: Array[StringName] = []
