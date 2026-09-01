## Message dialogs for the dashboard tabs.
##
## Both tabs built an AcceptDialog the same way, and both had to remember the
## part that matters: a dialog that is add_child()ed and never freed leaks a
## node per message. Two copies meant two places to forget it.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT

@tool
class_name DashboardDialogs extends RefCounted


## Show `message` under `parent`, freeing the dialog once it is dismissed.
##
## An empty `title` leaves Godot's own default, so a caller that never set one
## keeps the dialog it had.
static func show_message(parent: Node, message: String, title: String = "") -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	if not title.is_empty():
		dialog.title = title
	dialog.dialog_text = message
	parent.add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
