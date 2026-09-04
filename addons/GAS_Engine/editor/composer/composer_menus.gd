## The menus the Composer opens, and what each one offers.
##
## Two lists, because a card and a pin are different things: the card's items are
## about the statement and the pin's are about the wires on it. Offering one list
## for both would put Remove in front of somebody who right-clicked a cable.
##
## It offers and reports, and does neither of the two things that matter: it does
## not decide whether the file may be written, and it does not perform anything.
## Both belong to the screen, which is why this can grow - TASK 12's catalog, a
## menu on the background - without any of that growth landing there.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerMenus extends Node

## What can be done to a statement.
const REMOVE: String = "Remove"
const REPEAT: String = "Repeat"
const COPY: String = "Copy"

## What can be done to a pin.
const BREAK_ALL: String = "Break all wires"

const FOR_CARD: Array[String] = [REMOVE, REPEAT, COPY]
const FOR_PIN: Array[String] = [BREAK_ALL]

## Which item was picked, and what it was opened on. The two travel together
## because the answer arrives long after the question.
signal chose(item: String, node_id: StringName, port_id: StringName)

var _card: ComposerCardMenu = null
var _pin: ComposerCardMenu = null


## Offer what can be done to a statement, where the pointer is.
func open_for_card(node_id: StringName, at: Vector2) -> void:
	_card = _ready_menu(_card, FOR_CARD)
	_card.open_at(at, node_id)


## Offer what can be done to a pin.
func open_for_pin(node_id: StringName, port_id: StringName, at: Vector2) -> void:
	_pin = _ready_menu(_pin, FOR_PIN)
	_pin.open_at(at, node_id, port_id)


## The menu, made the first time it is wanted.
##
## Made late rather than in `_ready`: a Composer nobody right-clicks never needs
## either of these, and a popup that exists is a window the editor has to keep.
func _ready_menu(menu: ComposerCardMenu, items: Array[String]) -> ComposerCardMenu:
	if menu != null:
		return menu
	var made: ComposerCardMenu = ComposerCardMenu.new()
	made.offer(items)
	made.chose.connect(
		func _picked(item: String, node_id: StringName, port_id: StringName) -> void:
			chose.emit(item, node_id, port_id)
	)
	add_child(made)
	return made
