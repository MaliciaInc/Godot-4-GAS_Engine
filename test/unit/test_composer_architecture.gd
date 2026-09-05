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
## Where the Composer's production code lives, and nothing else does.
const COMPOSER_DIR: String = "res://addons/GAS_Engine/editor/composer"

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


## Every production file of the Composer, by path.
##
## Read off the folder rather than off a list: a gate that scans the files
## somebody remembered to name cannot see the one they added afterwards.
func _composer_sources() -> Dictionary[String, String]:
	var found: Dictionary[String, String] = {}
	for file_name: String in DirAccess.get_files_at(COMPOSER_DIR):
		if not file_name.ends_with(A_SCRIPT):
			continue
		var at: String = COMPOSER_DIR + "/" + file_name
		found[at] = FileAccess.get_file_as_string(at)
	return found


## Whether `source` names `identifier` as code: a whole word, outside comments.
##
## Whole word because ComposerWiringRoutes is a live class whose name starts
## with a retired one, and a gate matching on substrings would fail on the very
## file that replaced what it is guarding against.
func _names(source: String, identifier: String) -> bool:
	var pattern: RegEx = RegEx.create_from_string("\\b" + identifier + "\\b")
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		if pattern.search(line) != null:
			return true
	return false


## Every global class the project declares, and the file it comes from.
func _declared_classes() -> Dictionary[String, String]:
	var declared: Dictionary[String, String] = {}
	for described: Dictionary in ProjectSettings.get_global_class_list():
		declared[described["class"]] = described["path"]
	return declared


## The scan itself, proven against the one case that would quietly break it.
##
## `ComposerWiringRoutes` is a live class whose name begins with a retired one.
## A scanner matching substrings would report the file that replaced the old
## wiring as the old wiring coming back; one that matched nothing at all would
## report every file as clean. Both look identical from the gates below, so the
## scan is made to answer both questions here before they are trusted.
func test_the_scan_tells_a_retired_name_from_the_one_that_replaced_it() -> void:
	var live: String = FileAccess.get_file_as_string(
		COMPOSER_DIR + "/composer_wiring_routes.gd"
	)
	assert_false(live.is_empty(), "the file that replaced the old wiring was read")

	assert_true(_names(live, "ComposerWiringRoutes"), "the scan finds a live name")
	assert_false(_names(live, "ComposerWiring"), "and does not mistake it for the old one")
	assert_false(_names(live, "ComposerWire"), "nor for the one before that")


## The Blueprint's architecture, present and reachable by name.
func test_every_class_the_interaction_model_needs_is_declared() -> void:
	var declared: Dictionary[String, String] = _declared_classes()
	assert_gt(REQUIRED.size(), 0, "there are classes to require")

	for wanted: String in REQUIRED:
		assert_true(declared.has(wanted), "%s is declared" % wanted)
		if declared.has(wanted):
			assert_true(
				declared[wanted].begins_with(COMPOSER_DIR + "/"),
				"%s comes out of the Composer's own folder" % wanted
			)


## And the renderers it replaced are gone, not merely unused.
func test_no_retired_renderer_is_still_declared() -> void:
	var declared: Dictionary[String, String] = _declared_classes()

	for gone: String in RETIRED:
		assert_false(declared.has(gone), "%s is not a class any more" % gone)


## Nothing in the Composer names them either.
##
## A class can be deleted and still be reached for - by a preload, in a type
## annotation, in a comparison somebody left behind. This is the check that says
## the replacement is the only implementation.
func test_no_production_file_names_a_retired_renderer() -> void:
	var sources: Dictionary[String, String] = _composer_sources()
	assert_gt(sources.size(), 20, "the Composer's files were actually read")

	for at: String in sources:
		for gone: String in RETIRED:
			assert_false(
				_names(sources[at], gone), "%s does not name %s" % [at.get_file(), gone]
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
	var sources: Dictionary[String, String] = _composer_sources()
	assert_gt(sources.size(), 20, "the Composer's files were actually read")

	for at: String in sources:
		assert_false(
			sources[at].contains(A_DROPPED_NODE),
			"%s reports placements rather than drops" % at.get_file()
		)


## Moving a card never reorders the ability.
##
## Where a card sits is where it is drawn; when it happens is the order of the
## statements. Dragging one used to be both, which meant tidying a graph changed
## what the ability did.
func test_moving_a_card_never_reorders_the_ability() -> void:
	var screen: String = FileAccess.get_file_as_string(
		COMPOSER_DIR + "/composer_screen.gd"
	)
	assert_false(screen.is_empty(), "the screen was read")

	assert_false(
		screen.contains(A_REORDER_FROM_A_DRAG),
		"placement is placement; reordering is asked for on purpose"
	)
	assert_true(
		screen.contains(A_PLACEMENT),
		"and the screen does place cards, so the check above had something to miss"
	)


## Nothing in the Composer evaluates what it reads.
##
## The reader is handed whatever somebody has open, including a file they are
## halfway through typing. An editor panel that evaluates that text runs it.
func test_nothing_in_the_composer_evaluates_what_it_reads() -> void:
	var sources: Dictionary[String, String] = _composer_sources()
	assert_gt(sources.size(), 20, "the Composer's files were actually read")

	for at: String in sources:
		assert_false(
			_names(sources[at], AN_EVALUATOR),
			"%s reads the file rather than running it" % at.get_file()
		)


## The graph lives in the GDScript and nowhere else.
##
## A sidecar next to the script is a second place the truth could be, and the
## two disagree the first time somebody edits the file in the script editor,
## checks out a branch, or merges.
func test_the_graph_is_kept_in_the_gdscript_and_nowhere_else() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(COMPOSER_DIR)
	assert_gt(files.size(), 20, "the folder was actually read")

	for file_name: String in files:
		for suffix: String in SIDECAR_SUFFIXES:
			assert_false(
				file_name.ends_with(suffix),
				"%s is not a graph kept beside the code" % file_name
			)
#endregion
