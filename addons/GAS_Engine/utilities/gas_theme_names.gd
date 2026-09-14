## The names Godot's own theme knows things by.
##
## A theme is addressed by string - a size is `"font_size"` on type `"Label"` -
## and those strings are Godot's vocabulary rather than this project's. Both
## halves of the addon need some of them: the surfaces drawn inside the editor,
## and the overlay a running game draws for itself. Named here rather than beside
## the editor's theme because a running game must name nothing under `editor/`,
## and a second spelling of one of them is a second place to get it wrong.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GASThemeNames extends RefCounted

## The size a control that draws text reads its font at.
const FONT_SIZE: String = "font_size"

## The size a Tree draws its column titles at - its own item, not `FONT_SIZE`.
const TITLE_BUTTON_FONT_SIZE: String = "title_button_font_size"

const LABEL_TYPE: StringName = &"Label"
const BUTTON_TYPE: StringName = &"Button"
const TREE_TYPE: StringName = &"Tree"
