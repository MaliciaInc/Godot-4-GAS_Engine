## What can be done to a card, offered where the pointer is.
##
## The same operations the chords do, said out loud. A tool whose only way in is
## a chord is a tool you have to be told about, and nobody is there to tell
## somebody opening it for the first time.
##
## It offers and nothing more. Which operations exist, whether the file may be
## written, and what each one does to the source are all the screen's - this
## knows a list of names and which one was clicked. Keeping it that way is what
## lets the menu grow (a pin's own menu, a background menu, a catalog to search)
## without any of that growth landing in the screen.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCardMenu extends PopupMenu

## Which entry was picked, and what it was opened on.
##
## By the name it was offered under rather than by its index: an index is a
## number two lists have to agree about, and they stop agreeing the first time
## somebody inserts an item.
##
## What it was opened on travels with it, because the answer arrives long after
## the question - a menu is open while somebody reads it, and a caller holding
## "which pin was that" in a field of its own is a caller whose field is stale
## the moment a second menu opens.
signal chose(item: String, node_id: StringName, port_id: StringName)

var _items: Array[String] = []
var _node_id: StringName = &""
var _port_id: StringName = &""


## Offer these, in this order.
func offer(items: Array[String]) -> void:
	_items = items
	clear()
	for item: String in _items:
		add_item(item)
	if not id_pressed.is_connected(_on_id_pressed):
		id_pressed.connect(_on_id_pressed)


## Open it at a point in the viewport.
##
## `reset_size()` first: a popup reused from a previous open keeps the size it
## had, so a menu that once held more items opens with empty space below them.
func open_at(at: Vector2, node_id: StringName = &"", port_id: StringName = &"") -> void:
	_node_id = node_id
	_port_id = port_id
	reset_size()
	position = Vector2i(at)
	popup()


func _on_id_pressed(chosen: int) -> void:
	if chosen < 0 or chosen >= _items.size():
		return
	chose.emit(_items[chosen], _node_id, _port_id)
