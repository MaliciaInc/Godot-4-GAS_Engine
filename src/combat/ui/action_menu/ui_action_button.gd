## One ability, offered.
##
## Shows what the ability calls itself and what it looks like, and nothing else.
## Whether it can be used is decided by the component and handed down as
## `disabled`; a button that worked that out for itself would be a second
## authority on affordability.
##
## @meta_license: MIT
class_name UIActionButton extends TextureButton

var ability: BattlerAbility = null:
	set(value):
		ability = value
		if not is_inside_tree():
			await ready
		if ability == null:
			return
		_icon.texture = ability.icon
		_name_label.text = ability.display_name
		await get_tree().process_frame
		custom_minimum_size = $MarginContainer.size

## The handle this button stands for. Selection travels as a handle, not as the
## instance behind it: the instance is the component's to hand out, and a menu
## holding one past its turn would be holding something the runtime may have
## already retired.
var handle: GameplayAbilityHandle = null

## Dimmed rather than hidden: a player deciding what to save energy for is
## still reading these, so the icon has to stay recognisable.
const UNAVAILABLE_TINT: Color = Color(1.0, 1.0, 1.0, 0.4)

## Whether the player may press this right now.
##
## Sets `disabled` and shows it. A bare disabled TextureButton looks identical
## to a live one, so the engine refuses the press and the player is left
## without a reason - which reads as the game ignoring them rather than as an
## ability they cannot afford yet.
var available: bool = true:
	set(value):
		available = value
		disabled = not available
		if not is_inside_tree():
			await ready
		modulate = Color.WHITE if available else UNAVAILABLE_TINT

@onready var _icon: TextureRect = $MarginContainer/Items/Icon as TextureRect
@onready var _name_label: Label = $MarginContainer/Items/Name as Label


func _ready() -> void:
	pressed.connect(release_focus)
