## The menu of components an effect can be given.
##
## Read off the components directory rather than written out here. A list would
## be right today and wrong the first time somebody adds a thirteenth, and the
## wrongness would be silent: the component would exist, the runtime would read
## it, and nobody could author it.
##
## An entry the effect cannot take a second of is shown and disabled rather than
## hidden. Hidden, an author looks for it and concludes the addon has no such
## component; disabled with the reason on it, they learn the effect already has
## one.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name EffectComponentMenu extends PopupMenu

## Where the components live. One constant rather than twelve paths.
const COMPONENTS_DIRECTORY: String = "res://addons/GAS_Engine/effects/components"

## The base every component extends, which is not itself a component anybody
## adds.
const BASE_SCRIPT: String = "gameplay_effect_component.gd"

const SUFFIX: String = "_component.gd"

## Said on an entry the effect already has the only one of.
const ALREADY_HELD: String = "%s (already on this effect)"

## An author picked a component. The script, not an instance: whoever asked is
## the one that decides when to build it.
signal component_chosen(component_script: Script)

## What each menu index offers, in the order the menu shows them.
var _offered: Array[Script] = []


func _ready() -> void:
	id_pressed.connect(_on_id_pressed)


## Fill the menu for one effect, disabling what it cannot take another of.
##
## Rebuilt on every open rather than kept in step with edits: a menu that
## cached would be a second record of what is on the effect, and the two would
## disagree the moment a component was removed from somewhere else.
func offer_for(document: GameplayEffectDocument) -> void:
	clear()
	_offered.clear()
	for script: Script in available_components():
		var made: GameplayEffectComponent = script.new() as GameplayEffectComponent
		if made == null:
			continue
		var held: bool = (
			not made.allows_duplicates() and document.holds_kind_of(made) != null
		)
		var shown: String = readable_name(script)
		add_item(ALREADY_HELD % shown if held else shown, _offered.size())
		set_item_disabled(get_item_index(_offered.size()), held)
		_offered.append(script)


## Every component script a project can add, in a stable order.
##
## Sorted by file name so the menu does not reorder itself between runs: a menu
## whose entries move is a menu people misclick.
static func available_components() -> Array[Script]:
	var found: Array[Script] = []
	var names: Array[String] = []
	for name: String in DirAccess.get_files_at(COMPONENTS_DIRECTORY):
		if name.ends_with(SUFFIX) and name != BASE_SCRIPT:
			names.append(name)
	names.sort()
	for name: String in names:
		var script: Script = load(COMPONENTS_DIRECTORY + "/" + name) as Script
		if script != null:
			found.append(script)
	return found


## What to call a component in a menu.
##
## Derived from the file name rather than from a table: a table is a second
## place to change when one is renamed, and a menu entry that still says the old
## name is how somebody adds the wrong thing.
static func readable_name(script: Script) -> String:
	var file: String = script.resource_path.get_file()
	var stem: String = file.trim_suffix(SUFFIX).trim_prefix("gameplay_effect_")
	return stem.replace("_", " ").capitalize()


func _on_id_pressed(id: int) -> void:
	if id < 0 or id >= _offered.size():
		return
	component_chosen.emit(_offered[id])
