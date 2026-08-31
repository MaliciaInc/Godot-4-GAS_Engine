## Purely descriptive data for a UI to draw an effect by - never consulted by
## runtime logic. A game can extend this with a subclass for its own display
## needs.
##
## @meta_addon: GodotGAS, Arhalies fork
## @meta_license: MIT
class_name GameplayEffectUIDataComponent extends GameplayEffectComponent

@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D = null
