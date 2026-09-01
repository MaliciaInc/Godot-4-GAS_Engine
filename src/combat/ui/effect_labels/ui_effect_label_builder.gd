## The numbers that float up off a battler when something lands on it.
##
## Driven by what the battler reports, which is driven by what its component
## composed - so the number the player reads is the number the fight actually
## applied, after defences and clamps, not the one an ability intended.
##
## @meta_license: MIT
class_name UIEffectLabelBuilder extends Node2D

@export var damage_label_scene: PackedScene
@export var missed_label_scene: PackedScene


func setup(roster: BattlerRoster) -> void:
	for battler: Battler in roster.get_battlers():
		battler.damaged.connect(
			func _on_damaged(amount: float) -> void:
				var label: UIDamageLabel = damage_label_scene.instantiate() as UIDamageLabel
				add_child(label)
				label.setup(battler.anim.top.global_position, int(roundf(amount)))
		)
		battler.evaded.connect(
			func _on_evaded() -> void:
				var label: Node2D = missed_label_scene.instantiate() as Node2D
				add_child(label)
				label.global_position = battler.anim.top.global_position
		)
