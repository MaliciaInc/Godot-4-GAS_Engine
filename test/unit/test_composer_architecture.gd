## The shape of the Composer, asked of the tree rather than promised in a plan.
##
## Every claim here is one a refactor can quietly undo: a class deleted and then
## reached for again, a hand-written renderer creeping back beside the widget
## that replaced it, a graph that starts keeping itself in a file next to the
## script. None of them break a test about reading or writing an ability, which
## is exactly why they are worth a gate of their own - the day one of them goes
## wrong, the suite would otherwise stay green and the Composer would have two
## opinions about where a cable goes.
##
## It lives beside test_composer_gates.gd rather than inside it: that file holds
## the properties of the projection and the vocabulary, and both files together
## would be past the size the line gate allows. Two responsibilities, two files,
## no exception asked for.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

#region ARCHITECTURE_STABLE

## The classes the Blueprint interaction model is made of.
##
## Named here so that removing one is a decision somebody makes rather than a
## file that quietly stops being loaded. Every one of them is a class the plan
## either adds or rebuilds, and each has to be declared out of the Composer's
## own folder - a name resolving somewhere else is a second implementation
## wearing the right label.
const REQUIRED: Array[String] = [
	"ComposerFlow",
	"ComposerFlowEdits",
	"ComposerConnectionController",
	"ComposerStatementFactory",
	"ComposerValueCodec",
	"ComposerValueEditor",
	"ComposerPortTypes",
	"ComposerActionMenu",
	"ComposerNode",
	"ComposerGraph",
	"ComposerTypes",
	"ComposerCatalog",
	"ComposerReader",
	"ComposerSubset",
	"ComposerWriter",
	"ComposerDocument",
	"ComposerLayoutMetadata",
	"ComposerLayout",
	"ComposerCanvas",
	"ComposerCard",
	"ComposerInspector",
	"ComposerScreen",
	"ComposerPalette",
]

## The hand-written renderers GraphEdit replaced, and the selection tracker that
## went with them.
##
## Each was a second opinion about where a port is, which cable is under the
## pointer, and what is picked. One of those coming back is not an addition, it
## is the disagreement returning.
const RETIRED: Array[String] = [
	"ComposerWire",
	"ComposerWiring",
	"ComposerSelection",
]

## Names for things that would mean the graph had escaped the GDScript.
const A_DROPPED_NODE: String = "node_dropped"
const A_REORDER_FROM_A_DRAG: String = ".move("
const AN_EVALUATOR: String = "Expression"

## What the screen does instead: it writes down where a card was left.
const A_PLACEMENT: String = "place_many("

## What a graph is allowed to be kept in, and what it is not.
const SIDECAR_SUFFIXES: Array[String] = [".json", ".tres", ".res", ".cfg"]
const A_SCRIPT: String = ".gd"


## The scan itself, proven against the one case that would quietly break it.
##
## `ComposerWiringRoutes` is a live class whose name begins with a retired one.
## A scanner matching substrings would report the file that replaced the old
## wiring as the old wiring coming back; one that matched nothing at all would
## report every file as clean. Both look identical from the gates below, so the
## scan is made to answer both questions here before they are trusted.
func test_the_scan_tells_a_retired_name_from_the_one_that_replaced_it() -> void:
	var live: String = FileAccess.get_file_as_string(
		ComposerSourceScan.DIR + "/composer_wiring_routes.gd"
	)
	assert_false(live.is_empty(), "the file that replaced the old wiring was read")

	assert_true(ComposerSourceScan.names(live, "ComposerWiringRoutes"), "the scan finds a live name")
	assert_false(ComposerSourceScan.names(live, "ComposerWiring"), "and does not mistake it for the old one")
	assert_false(ComposerSourceScan.names(live, "ComposerWire"), "nor for the one before that")


## The Blueprint's architecture, present and reachable by name.
func test_every_class_the_interaction_model_needs_is_declared() -> void:
	var declared: Dictionary[String, String] = ComposerSourceScan.declared_classes()
	assert_gt(REQUIRED.size(), 0, "there are classes to require")

	for wanted: String in REQUIRED:
		assert_true(declared.has(wanted), "%s is declared" % wanted)
		if declared.has(wanted):
			assert_true(
				declared[wanted].begins_with(ComposerSourceScan.DIR + "/"),
				"%s comes out of the Composer's own folder" % wanted
			)


## And the renderers it replaced are gone, not merely unused.
func test_no_retired_renderer_is_still_declared() -> void:
	var declared: Dictionary[String, String] = ComposerSourceScan.declared_classes()

	for gone: String in RETIRED:
		assert_false(declared.has(gone), "%s is not a class any more" % gone)


## Nothing in the Composer names them either.
##
## A class can be deleted and still be reached for - by a preload, in a type
## annotation, in a comparison somebody left behind. This is the check that says
## the replacement is the only implementation.
func test_no_production_file_names_a_retired_renderer() -> void:
	var sources: Dictionary[String, String] = ComposerSourceScan.sources()
	assert_gt(sources.size(), 20, "the Composer's files were actually read")

	for at: String in sources:
		for gone: String in RETIRED:
			assert_false(
				ComposerSourceScan.names(sources[at], gone), "%s does not name %s" % [at.get_file(), gone]
			)


## The canvas is the widget, rather than a surface that imitates one.
func test_the_canvas_is_a_graph_edit() -> void:
	var canvas: ComposerCanvas = ComposerCanvas.new()
	add_child_autofree(canvas)

	assert_true(canvas is GraphEdit, "hit-testing, panning and zooming are its own")


## And a card is a node on it, so its ports are where the widget says they are.
func test_a_card_is_a_graph_node() -> void:
	var card: ComposerCard = ComposerCard.new()
	autofree(card)

	assert_true(card is GraphNode, "one authority over where a port is")


## Nothing is dropped on the floor.
##
## `node_dropped` was the old surface's way of saying a card had been let go
## somewhere; the widget reports its own placements now, and a second channel
## for the same event is two answers to where a card ended up.
func test_no_card_is_dropped_on_the_composer_floor() -> void:
	var sources: Dictionary[String, String] = ComposerSourceScan.sources()
	assert_gt(sources.size(), 20, "the Composer's files were actually read")

	for at: String in sources:
		assert_false(
			sources[at].contains(A_DROPPED_NODE),
			"%s reports placements rather than drops" % at.get_file()
		)


## Nothing in the Composer evaluates what it reads.
##
## The reader is handed whatever somebody has open, including a file they are
## halfway through typing. An editor panel that evaluates that text runs it.
func test_nothing_in_the_composer_evaluates_what_it_reads() -> void:
	var sources: Dictionary[String, String] = ComposerSourceScan.sources()
	assert_gt(sources.size(), 20, "the Composer's files were actually read")

	for at: String in sources:
		assert_false(
			ComposerSourceScan.names(sources[at], AN_EVALUATOR),
			"%s reads the file rather than running it" % at.get_file()
		)


## The graph lives in the GDScript and nowhere else.
##
## A sidecar next to the script is a second place the truth could be, and the
## two disagree the first time somebody edits the file in the script editor,
## checks out a branch, or merges.
func test_the_graph_is_kept_in_the_gdscript_and_nowhere_else() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(ComposerSourceScan.DIR)
	assert_gt(files.size(), 20, "the folder was actually read")

	for file_name: String in files:
		for suffix: String in SIDECAR_SUFFIXES:
			assert_false(
				file_name.ends_with(suffix),
				"%s is not a graph kept beside the code" % file_name
			)
#endregion


#region Standing somewhere else
## The Composer looks the same wherever it is standing.
##
## Every part of it is an ordinary Godot control, and an ordinary Godot control
## reads its font off the ambient theme. Inside the editor that reads right by
## accident, because the editor's theme is quiet. Standing in a game whose theme
## says 96, GraphEdit's own zoom row - the widget's chrome, not this project's -
## grew until it covered the first cards in the graph and swallowed every click
## on them. The Composer was unusable in the one place it had to work, and there
## was no way to see that from inside the editor.
func test_the_canvas_draws_its_own_chrome_at_the_composers_size() -> void:
	var loud: Theme = Theme.new()
	loud.default_font_size = A_LOUD_SIZE
	for kind: StringName in ComposerTheme.CHROME_TYPES:
		loud.set_font_size(GASEditorTheme.FONT_SIZE, kind, A_LOUD_SIZE)
	var host: Control = Control.new()
	host.theme = loud
	add_child_autofree(host)

	var canvas: ComposerCanvas = ComposerCanvas.new()
	host.add_child(canvas)
	await get_tree().process_frame

	var chrome: Array[Control] = _chrome_of(canvas)
	assert_gt(chrome.size(), 0, "the widget draws chrome of its own")
	for drawn: Control in chrome:
		assert_eq(
			drawn.get_theme_font_size(GASEditorTheme.FONT_SIZE),
			ComposerTheme.FONT_VALUE,
			"%s draws at the Composer's size" % drawn.get_class()
		)

	var bare: Control = Control.new()
	host.add_child(bare)
	await get_tree().process_frame
	assert_eq(
		bare.get_theme_font_size(GASEditorTheme.FONT_SIZE, &"Button"), A_LOUD_SIZE,
		"and the host really was saying something else"
	)
	canvas.queue_free()


## The widget's own toolbar is not drawn over the graph.
##
## GraphEdit floats a zoom row, a grid toggle and a snap box over the top-left
## of the canvas. The layout puts the first card at exactly that corner, so the
## Entry card's title bar - the strip somebody grabs it by - and its output pin
## were both underneath it, and no click on either reached the card. That was
## true in the editor too; it took drawing the Composer in a project whose theme
## made the row large enough to notice.
func test_the_widgets_own_toolbar_is_not_drawn_over_the_graph() -> void:
	var canvas: ComposerCanvas = ComposerCanvas.new()
	add_child_autofree(canvas)
	await get_tree().process_frame

	assert_false(canvas.show_menu, "the widget's toolbar is off")
	assert_false(
		canvas.get_menu_hbox().is_visible_in_tree(), "and nothing of it is drawn"
	)


## What a host theme says when it is not thinking about this addon.
const A_LOUD_SIZE: int = 96


## The controls the widget builds for itself, a SpinBox's line edit included:
## that is the one that draws the number, and it is not the SpinBox.
func _chrome_of(canvas: ComposerCanvas) -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in canvas.get_menu_hbox().get_children(true):
		var control: Control = child as Control
		if control == null:
			continue
		found.append(control)
		var spin: SpinBox = child as SpinBox
		if spin != null:
			found.append(spin.get_line_edit())
	return found
#endregion
