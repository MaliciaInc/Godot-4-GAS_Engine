## What kind of GraphEdit the Composer's canvas is.
##
## Six decisions about the widget rather than about the graph it draws, and each
## one is a policy somebody could reasonably have set the other way - so each is
## written down with its reason beside it, here, where they can be read together
## instead of scattered through a constructor.
##
## Nothing here draws, reads a gesture or touches a graph. It is handed a widget
## and says what kind of widget it is.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerCanvasSettings extends RefCounted


## Make `edit` the canvas this editor wants, zooming between `nearest` and
## `furthest`.
static func apply(edit: GraphEdit, nearest: float, furthest: float) -> void:
	# The widget's own chrome - the zoom row, the grid toggle, the snap box - is
	# drawn out of the ambient theme like any other control, so it is told the
	# Composer's size rather than the host's. Inside the editor that reads right
	# by accident; in a project whose theme is louder the row grew until it
	# covered the graph.
	edit.theme = ComposerTheme.own_chrome()

	# And then not drawn at all. GraphEdit floats that row over the top-left
	# corner of the canvas, which is exactly where the layout puts the first
	# card: the Entry card's title bar - the strip somebody grabs it by - and
	# its output pin were both underneath it, in the editor as much as anywhere
	# else. This screen has a bar of its own, zoom is on the wheel, and the snap
	# box is a second opinion about where a card lands.
	edit.show_menu = false

	# Off, deliberately. GraphEdit's right-disconnect is a second policy about
	# what a right-click on a wire means, and this editor already has one - right
	# click opens what can be done here, and disconnecting is one of the things
	# it offers. Two policies for one button is a button that does different
	# things depending on where in it you clicked.
	edit.right_disconnects = false

	# Nothing to show in miniature that the graph does not show already: an
	# ability is a handful of statements, not a landscape.
	edit.minimap_enabled = false

	# The grid is what makes a placement look deliberate rather than dropped.
	edit.show_grid = true

	edit.zoom_min = nearest
	edit.zoom_max = furthest
