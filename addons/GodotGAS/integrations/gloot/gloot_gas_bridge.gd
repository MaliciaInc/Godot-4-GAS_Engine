## Keeps an ability system in step with what one equipment slot holds.
##
## Bound to three members of a GLoot ItemSlot and two of what it contains, all
## checked before they are called. None of them belong to this addon, so a
## version that renamed one has to produce a refusal here rather than a crash
## somewhere later, where the cause would be several frames away from the error.
##
## Equipping is a transaction. Everything is built and validated before the ASC
## is touched, and a failure part-way through takes back what it already gave.
## That is also why a passive effect has to be silent: a rollback cannot un-play
## a cue or un-send an event that a listener has already acted on.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GlootGasBridge extends Node

signal equipment_applied(prototype_id: StringName)
signal equipment_removed(prototype_id: StringName)

## The slot held something this bridge could not grant: an unknown prototype, an
## ill-formed grant, or a step that failed and was rolled back.
signal equipment_rejected(prototype_id: StringName)

const EQUIPPED_SIGNAL: StringName = &"item_equipped"
const CLEARED_SIGNAL: StringName = &"cleared"
const GET_ITEM_METHOD: StringName = &"get_item"
const GET_PROTOTYPE_METHOD: StringName = &"get_prototype"
const GET_ID_METHOD: StringName = &"get_id"

var target_asc: AbilitySystemComponent = null
var catalog: GlootGasEquipmentCatalog = null

var _slot: Node = null

## What the currently worn item actually gave. Null when nothing is worn.
var _receipt: GlootGasEquipmentReceipt = null


#region Binding
## Listen to an ItemSlot-shaped node. False when anything needed is missing.
func bind(
	item_slot: Node, asc: AbilitySystemComponent, grant_catalog: GlootGasEquipmentCatalog
) -> bool:
	if item_slot == null or asc == null or grant_catalog == null:
		return false
	# An ambiguous catalogue is refused here, while somebody is still looking,
	# rather than answering confidently with the wrong sword later.
	if not grant_catalog.is_valid():
		return false
	if not item_slot.has_signal(EQUIPPED_SIGNAL) or not item_slot.has_signal(CLEARED_SIGNAL):
		return false
	if not item_slot.has_method(GET_ITEM_METHOD):
		return false

	unbind()

	_slot = item_slot
	target_asc = asc
	catalog = grant_catalog
	_slot.connect(EQUIPPED_SIGNAL, _on_item_equipped)
	_slot.connect(CLEARED_SIGNAL, _on_cleared)
	return true


## Stop listening, and take back whatever the worn item had given.
##
## Withdrawal happens first, while the ASC is still known. Letting go of an item
## slot must not leave its abilities on the wearer.
func unbind() -> void:
	_withdraw()
	if _slot != null:
		if _slot.is_connected(EQUIPPED_SIGNAL, _on_item_equipped):
			_slot.disconnect(EQUIPPED_SIGNAL, _on_item_equipped)
		if _slot.is_connected(CLEARED_SIGNAL, _on_cleared):
			_slot.disconnect(CLEARED_SIGNAL, _on_cleared)
	_slot = null
	target_asc = null
	catalog = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		unbind()


func _on_item_equipped() -> void:
	refresh_from_slot()


func _on_cleared(_item: Variant) -> void:
	_withdraw()
#endregion


#region Reading the slot
## Take back whatever is worn, then grant whatever the slot holds now.
##
## Replacing an item is these two in order, not a diff between them: working out
## what the two grants have in common would have to decide whether a tag both
## give should be removed and re-added, and the refcount already answers that.
func refresh_from_slot() -> void:
	_withdraw()
	if _slot == null or target_asc == null or catalog == null:
		return

	var prototype_id: StringName = _prototype_id_in_slot()
	if String(prototype_id).is_empty():
		return

	var grant: GlootGasEquipmentGrant = catalog.find(prototype_id)
	if grant == null or not grant.is_valid():
		equipment_rejected.emit(prototype_id)
		return
	_apply(grant)


## Walk from the slot to the prototype id, checking every step.
##
## Three method names this addon does not own, on three objects it did not
## make. Each is verified before it is called, and anything unexpected ends the
## walk with an empty answer - which the caller reads as "nothing to grant".
func _prototype_id_in_slot() -> StringName:
	var raw_item: Variant = _slot.call(GET_ITEM_METHOD)
	if not raw_item is Object:
		return &""
	var item: Object = raw_item
	if not item.has_method(GET_PROTOTYPE_METHOD):
		return &""

	var raw_prototype: Variant = item.call(GET_PROTOTYPE_METHOD)
	if not raw_prototype is Object:
		return &""
	var prototype: Object = raw_prototype
	if not prototype.has_method(GET_ID_METHOD):
		return &""

	var raw_id: Variant = prototype.call(GET_ID_METHOD)
	if raw_id is StringName:
		var named: StringName = raw_id
		return named
	if raw_id is String:
		var text: String = raw_id
		return StringName(text)
	return &""
#endregion


#region Granting and taking back
func _apply(grant: GlootGasEquipmentGrant) -> void:
	# Built and type-checked before the ASC is touched, so the likeliest failure
	# - a scene whose root is not an ability - costs nothing to discover.
	var abilities: Array[GameplayAbility] = []
	for scene: PackedScene in grant.abilities:
		var instance: Node = scene.instantiate()
		var ability: GameplayAbility = instance as GameplayAbility
		if ability == null:
			instance.queue_free()
			for built: GameplayAbility in abilities:
				built.queue_free()
			equipment_rejected.emit(grant.prototype_id)
			return
		abilities.append(ability)

	var receipt: GlootGasEquipmentReceipt = GlootGasEquipmentReceipt.new()
	receipt.prototype_id = grant.prototype_id

	for ability: GameplayAbility in abilities:
		target_asc.grant_ability(ability)
		receipt.granted_abilities.append(ability)

	for effect: GameplayEffect in grant.passive_effects:
		var applied: ActiveGameplayEffect = target_asc.apply_gameplay_effect(effect, target_asc)
		if applied == null:
			_take_back(receipt)
			equipment_rejected.emit(grant.prototype_id)
			return
		receipt.applied_effects.append(applied)

	for tag: StringName in grant.direct_tags:
		target_asc.add_tag(tag)
		receipt.added_tags.append(tag)

	_receipt = receipt
	equipment_applied.emit(grant.prototype_id)


## Undo exactly what a receipt records, in the reverse order it was given.
func _take_back(receipt: GlootGasEquipmentReceipt) -> void:
	for tag: StringName in receipt.added_tags:
		target_asc.remove_tag(tag)
	for applied: ActiveGameplayEffect in receipt.applied_effects:
		target_asc.remove_active_effect(applied)
	for ability: GameplayAbility in receipt.granted_abilities:
		target_asc.remove_ability(ability)


## Take back the worn item's grant, if there is one. Safe to call repeatedly.
func _withdraw() -> void:
	if _receipt == null:
		return
	var worn: GlootGasEquipmentReceipt = _receipt
	_receipt = null
	if target_asc == null:
		return
	_take_back(worn)
	equipment_removed.emit(worn.prototype_id)
#endregion
