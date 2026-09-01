## The icons a drafted attribute can be given, and the menus that offer them.
##
## One catalogue, so the dropdown, the inline popup and the tree row cannot
## disagree about which icons exist or what they are called. The draft stores
## the name, not the texture, so a renamed file is a missing icon rather than a
## corrupt draft.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT

@tool
class_name AttributeIcons extends RefCounted

## The name a draft falls back to, and the one legacy drafts were written with.
const DEFAULT_NAME: String = "Attribute"

const CATALOGUE: Dictionary[String, Texture2D] = {
	"Star": preload("res://addons/GAS_Engine/icons/gas_engine_icon_star.svg"),
	"Heart": preload("res://addons/GAS_Engine/icons/gas_engine_icon_heart.svg"),
	"Bolt": preload("res://addons/GAS_Engine/icons/gas_engine_icon_bolt.svg"),
	"Shield": preload("res://addons/GAS_Engine/icons/gas_engine_icon_shield.svg"),
	"Sword": preload("res://addons/GAS_Engine/icons/gas_engine_icon_sword.svg"),
}


## The icon for a stored name, or `fallback` when the name is unknown.
##
## An unknown name is normal: it is what a legacy draft holds, and what remains
## after an icon is removed from the catalogue.
static func texture_for(name: String, fallback: Texture2D) -> Texture2D:
	return CATALOGUE.get(name, fallback)


static func names() -> Array[String]:
	var listed: Array[String] = []
	for name: String in CATALOGUE.keys():
		listed.append(name)
	return listed


## Fill a dropdown with the catalogue.
static func fill_dropdown(button: OptionButton) -> void:
	if button == null:
		return
	button.clear()
	for name: String in names():
		button.add_icon_item(CATALOGUE[name], name)


## Build the inline popup and return the names in menu-id order.
##
## The order is returned rather than assumed, because the popup reports the id
## it was given and a caller that recomputed the order separately would map the
## wrong icon the moment the catalogue changed.
static func fill_popup(popup: PopupMenu) -> Array[String]:
	var ordered: Array[String] = []
	if popup == null:
		return ordered
	for name: String in names():
		popup.add_icon_item(CATALOGUE[name], name, ordered.size())
		ordered.append(name)
	return ordered
