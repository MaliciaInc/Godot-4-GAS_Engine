## The runtime overlay, standing in a game whose theme is not quiet.
##
## The overlay is the one piece of the addon a game puts in its own tree, and a
## Control that does not say how big its text is takes the answer from whatever
## theme it is standing in. In the editor that is quiet, and the overlay looked
## right. In a game whose theme says 96 - the sandbox's does - its heading and
## its table came out at 96, and a panel anchored to half a 1920 by 1080 screen
## measured 1193 by 1408, with room for eight of that game's nine attributes.
## It is the defect the Composer had, one folder over.
##
## A game's theme is stood in for by Godot's fallback theme, raised to 96 for the
## types the overlay draws. Not the root window's: the overlay is a CanvasLayer,
## and a theme set on a window does not reach a Control through one - which is
## how the first version of this file passed against nothing.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

## What the game's theme says.
const LOUD: int = 96

## What the overlay draws at when no game has said otherwise: Godot's own size.
const OWN_SIZE: int = 16

## Half the screen the defect was measured on, which is what the panel is
## anchored to there.
const HALF_THE_MEASURED_SCREEN: float = 960.0

const FONT_SIZE: StringName = &"font_size"
const TITLE_SIZE: StringName = &"title_button_font_size"


## One size the fallback theme held before this raised it, put back afterwards.
class Held extends RefCounted:
	var kind: StringName = &""
	var item: StringName = &""
	var had: bool = false
	var size: int = 0


var _held: Array[Held] = []


func before_each() -> void:
	_held.clear()
	_raise(&"Label", FONT_SIZE)
	_raise(&"Button", FONT_SIZE)
	_raise(&"Tree", FONT_SIZE)
	_raise(&"Tree", TITLE_SIZE)


func after_each() -> void:
	var fallback: Theme = ThemeDB.get_default_theme()
	for one: Held in _held:
		if one.had:
			fallback.set_font_size(one.item, one.kind, one.size)
		else:
			fallback.clear_font_size(one.item, one.kind)
	_held.clear()


func _raise(kind: StringName, item: StringName) -> void:
	var fallback: Theme = ThemeDB.get_default_theme()
	var one: Held = Held.new()
	one.kind = kind
	one.item = item
	one.had = fallback.has_font_size(item, kind)
	one.size = fallback.get_font_size(item, kind) if one.had else 0
	_held.append(one)
	fallback.set_font_size(item, kind, LOUD)


func _overlay() -> GasDebugOverlay:
	var made: GasDebugOverlay = (load(GasDebugOverlay.SCENE) as PackedScene).instantiate() as GasDebugOverlay
	add_child_autofree(made)
	return made


func test_the_overlay_draws_its_text_at_its_own_size_whatever_the_game_s_theme_says() -> void:
	var bystander: Label = Label.new()
	add_child_autofree(bystander)
	assert_eq(bystander.get_theme_font_size(FONT_SIZE), LOUD, "a Label that says nothing is drawn at the game's size")

	var overlay: GasDebugOverlay = _overlay()
	var heading: Label = overlay.get_node("Panel/Body/Heading") as Label
	var table: Tree = overlay.get_node("Panel/Body/Table") as Tree
	var tabs: HBoxContainer = overlay.get_node("Panel/Body/Tabs") as HBoxContainer

	assert_eq(heading.get_theme_font_size(FONT_SIZE), OWN_SIZE, "the heading")
	assert_eq(table.get_theme_font_size(FONT_SIZE), OWN_SIZE, "the table")
	assert_eq(table.get_theme_font_size(TITLE_SIZE), OWN_SIZE, "the table's column titles")
	assert_gt(tabs.get_child_count(), 0, "there are tabs to measure")
	for tab: Node in tabs.get_children():
		assert_eq((tab as Button).get_theme_font_size(FONT_SIZE), OWN_SIZE, "the %s tab" % (tab as Button).text)


## Anchored to half the screen, it has to fit in half the screen.
func test_the_panel_needs_no_more_than_half_the_screen_it_was_measured_on() -> void:
	var overlay: GasDebugOverlay = _overlay()
	await wait_frames(2)
	var panel: Control = overlay.get_node("Panel") as Control

	assert_lte(panel.get_combined_minimum_size().x, HALF_THE_MEASURED_SCREEN, "its tabs and table fit the half it was given")
