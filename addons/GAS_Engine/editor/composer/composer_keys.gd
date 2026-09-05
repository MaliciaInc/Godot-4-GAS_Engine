## The editor actions the Composer listens for, named once.
##
## Godot's own input actions, spelled here rather than at each call site. Two
## panels asking for `ui_cancel` by hand is two strings that have to stay the
## same and nothing that says so - and a key nobody can press because one of them
## has a typo is a key that looks broken rather than misspelled.
##
## These are Godot's names, not this project's, which is why they are recorded
## rather than invented: nothing here may rename them.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerKeys extends RefCounted

## Escape: put it back the way it was and close.
const CANCEL: StringName = &"ui_cancel"

## Moving through a list of choices.
const UP: StringName = &"ui_up"
const DOWN: StringName = &"ui_down"

## Taking the choice under the cursor. Two actions because a list and a line of
## text answer to different ones, and a menu that is both has to hear both.
const ACCEPT: StringName = &"ui_accept"
const SUBMIT: StringName = &"ui_text_submit"
