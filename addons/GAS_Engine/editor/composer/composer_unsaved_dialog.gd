## The three answers to leaving an ability with unsaved changes.
##
## Save, Discard and Cancel, and Cancel has to be one of them: a dialog that
## only offers the two destructive answers is a dialog somebody dismisses by
## accident and loses their work to.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerUnsavedDialog extends ConfirmationDialog

signal save_chosen
signal discard_chosen
signal cancel_chosen

var _discard_button: Button = null

func _ready() -> void:
	title = "Unsaved Ability"
	dialog_text = "This ability has unsaved changes."
	ok_button_text = "Save"

	_discard_button = add_button("Discard", false, "discard")
	_discard_button.pressed.connect(_on_discard)

	confirmed.connect(func() -> void: save_chosen.emit())
	canceled.connect(func() -> void: cancel_chosen.emit())


func _on_discard() -> void:
	hide()
	discard_chosen.emit()
