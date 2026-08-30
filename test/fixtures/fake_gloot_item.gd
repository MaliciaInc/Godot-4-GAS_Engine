## A stand-in for a GLoot item and the prototype behind it.
##
## Two methods, because two methods are all the bridge is allowed to know about:
## an item can be asked for its prototype, and a prototype for its id. Nothing
## else about a real InventoryItem is reachable from here, which is the point -
## if a test ever needs to add a field, the bridge has started reading item data
## to decide gameplay, and every loot edit becomes a balance change.
##
## @meta_license: MIT
class_name FakeGlootItem extends RefCounted


class Prototype extends RefCounted:
	var id: StringName = &""

	func _init(prototype_id: StringName) -> void:
		id = prototype_id

	func get_id() -> StringName:
		return id


var _prototype: Prototype = null


static func build(prototype_id: StringName) -> FakeGlootItem:
	var item: FakeGlootItem = FakeGlootItem.new()
	item._prototype = Prototype.new(prototype_id)
	return item


func get_prototype() -> Prototype:
	return _prototype
