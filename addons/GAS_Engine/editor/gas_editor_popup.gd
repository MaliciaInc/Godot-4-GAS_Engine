## A modal window over the inspector, opened the same way every time.
##
## Six properties and two calls, and every editor in this addon that needs a
## bigger surface than a property row was setting all of them itself. They are
## not interesting choices - a popup that was not transient would outlive the
## editor that opened it, and one that was not exclusive would let somebody edit
## the object behind it while a picker was still open on it.
##
## Opened rather than configured: the caller says what it is called and how big
## it is, and gets back a Window already on screen with its body still to fill.
##
## @meta_addon: GAS_Engine
## @meta_author: MaliciaInc
## @meta_license: GAS_Engine Community Use License 1.0

@tool
class_name GASEditorPopup extends RefCounted


## A modal window, centred over the editor and ready to be filled.
##
## `on_close` is connected to `close_requested` rather than assumed, because
## what closing means differs: one editor frees the window, another has a second
## one open on top of it to free first.
static func opened(title: String, size: Vector2i, on_close: Callable) -> Window:
	var window: Window = Window.new()
	window.title = title
	window.size = size
	window.transient = true
	window.exclusive = true
	window.close_requested.connect(on_close)

	EditorInterface.get_base_control().add_child(window)
	window.popup_centered()
	return window


## A container filling one of these windows, inset by `margin`.
##
## The other half of what every caller wrote out: a Window lays out nothing on
## its own, so a body added without this sits at its natural size in the corner.
static func body_of(window: Window, margin: int) -> VBoxContainer:
	var body: VBoxContainer = VBoxContainer.new()
	body.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, margin
	)
	window.add_child(body)
	return body
