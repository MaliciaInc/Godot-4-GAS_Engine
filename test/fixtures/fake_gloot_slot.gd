## A stand-in for a GLoot ItemSlot, carrying only its published contract.
##
## Two signals and one getter. It sets its contents before announcing them, the
## way the real slot does, because a bridge that read the slot on
## `item_equipped` and found it still empty would grant nothing and report
## success.
##
## @meta_license: MIT
class_name FakeGlootSlot extends Node

signal item_equipped()
signal cleared(item: Variant)

var _item: FakeGlootItem = null


static func build() -> FakeGlootSlot:
	var slot: FakeGlootSlot = FakeGlootSlot.new()
	slot.name = "ItemSlot"
	return slot


func get_item() -> FakeGlootItem:
	return _item


func equip(item: FakeGlootItem) -> void:
	_item = item
	item_equipped.emit()


func clear() -> void:
	var previous: FakeGlootItem = _item
	_item = null
	cleared.emit(previous)
