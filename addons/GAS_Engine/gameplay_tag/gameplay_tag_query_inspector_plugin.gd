## Offers the query editor wherever a `GameplayTagQuery` is authored.
##
## By the property's type rather than by its name: a query is a query wherever
## it appears - on an ability's activation requirements, on a target filter, on
## a tag relationship row - and a plugin matching on names would have to be told
## about each new place one turns up.
##
## The matching and Godot's seven-parameter override live in
## GASResourceInspectorPlugin, which the attribute picker uses too. What is here
## is the two things that differ: which class, and which editor.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends GASResourceInspectorPlugin

const QueryProperty = preload(
	"res://addons/GAS_Engine/gameplay_tag/gameplay_tag_query_editor_property.gd"
)

## The class a property must be for the editor to stand in for it.
const QUERY_CLASS: String = "GameplayTagQuery"


func edited_class() -> String:
	return QUERY_CLASS


func editor_for_property() -> EditorProperty:
	return QueryProperty.new()


## Whether a property holds a tag query.
static func is_a_tag_query(type: Variant.Type, hint_string: String) -> bool:
	return GASResourceInspectorPlugin.stands_in_for(type, hint_string, QUERY_CLASS)
