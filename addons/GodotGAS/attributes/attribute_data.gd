## One gameplay attribute: a durable base value and the effective value derived
## from it.
##
## `base_value` is NOT "the level stat that never changes". It is the durable
## underlying value after permanent and instant changes, with no active
## contributions applied. `current_value` is what the base becomes once the
## active contribution stack and the effective clamp are applied.
##
## Upstream's `base_value` setter assigned `current_value = new_value`, which
## made current a second source of truth: setting the base while a buff was
## active silently discarded the buff, and nothing ever recomputed it. Both
## fields are plain storage here. `GameplayAttributeRuntime` is the only thing
## allowed to derive one from the other, and it recomposes from scratch rather
## than replaying deltas.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_author: YulRun (https://YulRun.Dev), Arhalies fork
## @meta_license: MIT

@tool
@icon("res://addons/GodotGAS/icons/godot_gas_asc.svg")
class_name AttributeData extends Resource

## The durable underlying value. Instant effects and execution calculations
## write here; active modifiers never do.
@export var base_value: float = 0.0

## The effective value: the base plus every active contribution, clamped.
## Derived. Writing it directly bypasses the aggregator and the next
## recomposition will overwrite it.
@export var current_value: float = 0.0


func _init(initial_value: float = 0.0) -> void:
	base_value = initial_value
	current_value = initial_value
