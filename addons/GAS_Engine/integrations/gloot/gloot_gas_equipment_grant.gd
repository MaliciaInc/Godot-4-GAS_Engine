## What one kind of item gives whoever equips it.
##
## Keyed by the item's prototype id and nothing else. The bridge reads no other
## property off a GLoot item to decide gameplay: an inventory is authored by
## whoever is designing loot, and letting arbitrary item fields drive abilities
## would make every item edit a gameplay change nobody reviewed.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GlootGasEquipmentGrant extends Resource

@export var prototype_id: StringName = &""

## Scenes whose root is a GameplayAbility. Confirmed by instantiating, because a
## PackedScene cannot promise what it will produce.
@export var abilities: Array[PackedScene] = []

## Effects that last exactly as long as the item is worn.
@export var passive_effects: Array[GameplayEffect] = []

## Tags granted directly, through the ASC's ordinary refcount, so an item and a
## buff can both say "Sworn" and removing one leaves the other's.
@export var direct_tags: Array[StringName] = []


## Whether this grant can be applied at all, asked before anything is touched.
##
## A passive effect has to be INFINITE and silent: it is undone by removing it,
## and a rollback part-way through equipping cannot take back a cue that already
## played or an event a listener already acted on. Duration is wrong here too -
## an item's effect ends when the item comes off, not when a timer says so.
func is_valid() -> bool:
	if String(prototype_id).is_empty():
		return false

	for scene: PackedScene in abilities:
		if scene == null:
			return false

	for effect: GameplayEffect in passive_effects:
		if effect == null:
			return false
		if effect.policy != GameplayEffect.DurationPolicy.INFINITE:
			return false
		if not effect.is_silent():
			return false

	return true
