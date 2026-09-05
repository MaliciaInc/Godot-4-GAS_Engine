## What the Blueprint parity closure settled, checked against the files.
##
## The battery beside this one guards the shape the Composer was built in: which
## classes exist, what a canvas is, where a graph is allowed to live. This one
## guards what the closure phase decided on top of that - the classes it adds,
## the contracts a structural card is drawn from, and the three sentences that
## had to stop being true of the code.
##
## Two responsibilities, two files, no exception asked for. Both read the folder
## through the same scan, so neither can quietly disagree with the other about
## what is in it.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

## What a refusal of an execution move used to say, and a position taken and
## then thrown away. Both were true of the Composer and never of the file.
const A_REFUSED_EXECUTION_MOVE: String = "ComposerFlowEdits.NOT_REPRESENTABLE"
const AN_IGNORED_POSITION: String = "_at: Vector2"

## GraphEdit's own way of drawing a cable, which only the painter may ask for.
const A_DRAWN_CABLE: String = "connect_node("

## How a cable comes to be in a graph at all.
const A_JOINED_PAIR: String = "connections.append("

## What each file must not say, and what it says instead.
##
## Three claims of one shape, so one table. The second column is what proves the
## check had something to miss: a gate that only looks for an absence passes
## just as happily on a file it failed to read.
##
## Where a card sits is where it is drawn; when it happens is the order of the
## statements. Dragging one used to be both, which meant tidying a graph changed
## what the ability did. A run of control was said to be unmovable, which was
## true of the Composer and never of the person's file. And where a call was let
## go used to arrive at a handler that took the position and ignored it.
const SAYINGS: Array = [
	[
		"a card is placed, never reordered",
		"composer_screen.gd", ".move(", "place_many(",
	],
	[
		"a run of control is planned, not turned away",
		"composer_connection_moves.gd", A_REFUSED_EXECUTION_MOVE, "ComposerReader.wire(",
	],
	[
		"where a call was let go is written down",
		"composer_screen.gd", AN_IGNORED_POSITION, "insert_call_at(",
	],
]


func test_what_each_file_must_not_say() -> void:
	var checked: int = 0
	for row: Array in SAYINGS:
		var described: String = row[0]
		var file_name: String = row[1]
		var forbidden: String = row[2]
		var wanted: String = row[3]

		var source: String = ComposerSourceScan.source_of(file_name)

		assert_false(source.is_empty(), "%s: %s was read" % [described, file_name])
		assert_false(source.contains(forbidden), "%s: `%s` is gone" % [described, forbidden])
		assert_true(
			source.contains(wanted),
			"%s: and `%s` is there, so the check had something to miss" % [described, wanted]
		)
		checked += 1
	assert_eq(checked, SAYINGS.size(), "every file was read")


## The classes the closure phase adds, and what each one is the only home of.
##
## Named here so that removing one is a decision somebody makes rather than a
## file that quietly stops being loaded.
const REQUIRED_NOW: Array[String] = [
	"ComposerFlowBuilder",
	"ComposerFlowTransforms",
	"ComposerFlowPlaces",
	"ComposerFieldEdits",
	"ComposerEnumHint",
	"ComposerPinMenu",
]


func test_every_class_this_phase_adds_is_declared() -> void:
	var declared: Dictionary[String, String] = ComposerSourceScan.declared_classes()
	assert_gt(REQUIRED_NOW.size(), 0, "there are classes to require")

	for wanted: String in REQUIRED_NOW:
		assert_true(declared.has(wanted), "%s is declared" % wanted)
		var comes_from: String = declared.get(wanted, "")
		assert_true(
			comes_from.begins_with(ComposerSourceScan.DIR),
			"%s is the Composer's own, not a name resolving elsewhere" % wanted
		)


## The contracts a structural card is drawn from, each in the one file that owns
## it.
##
## Written as "this identifier appears in this file" rather than as behaviour
## because behaviour is what every other battery checks. What this catches is the
## contract being moved somewhere else and quietly re-invented in two places -
## which is how a branch ends up with a True pin the canvas draws and the reader
## has never heard of.
const CONTRACTS: Array = [
	["composer_reader.gd", "TRUE_OUT", "a branch's true path is named by the reader"],
	["composer_reader.gd", "FALSE_OUT", "and so is its false one"],
	["composer_reader.gd", "CASE_OUT", "a match's arms are numbered by the reader"],
	["composer_reader.gd", "UNMATCHED_OUT", "and its No Match named there too"],
	["composer_reader.gd", "CONDITION_IN", "a condition takes its cable by name"],
	["composer_reader.gd", "MATCH_VALUE_IN", "so does a match value"],
	["composer_reader.gd", "RETURN_VALUE_IN", "and what an end hands back"],
	["composer_value_shape.gd", "ENUM", "an enum argument has a shape of its own"],
	["composer_subset.gd", "FLOW_ELSE_MARK", "a generated else is marked as ours"],
	["composer_subset.gd", "FLOW_DEFAULT_MARK", "and so is a generated catch-all"],
]


func test_every_structural_contract_lives_where_it_is_owned() -> void:
	var sources: Dictionary[String, String] = ComposerSourceScan.sources()
	var checked: int = 0
	for row: Array in CONTRACTS:
		var file_name: String = row[0]
		var identifier: String = row[1]
		var described: String = row[2]

		var at: String = ComposerSourceScan.DIR + "/" + file_name
		assert_true(sources.has(at), "%s was read" % file_name)
		var read: String = sources.get(at, "")
		assert_true(ComposerSourceScan.names(read, identifier), described)
		checked += 1
	assert_eq(checked, CONTRACTS.size(), "every contract was looked for")


## Two files decide what is joined to what, and no others.
##
## Whether a cable exists is worked out from the text every time it is read: the
## builder decides what runs after what, the data wiring decides which value
## reaches which slot, and between them that is the whole graph. A third file
## appending a connection would be a cable on the canvas that nothing in the
## person's ability put there - and it would look exactly like a real one.
##
## Behaviour is checked elsewhere; what this catches is the decision moving.
const JOINING: Array[String] = [
	"composer_data_wires.gd",
	"composer_flow_builder.gd",
]


func test_only_two_files_decide_what_is_joined_to_what() -> void:
	var sources: Dictionary[String, String] = ComposerSourceScan.sources()
	var joining: Array[String] = []
	for at: String in sources:
		if sources[at].contains(A_JOINED_PAIR):
			joining.append(at.get_file())
	joining.sort()
	assert_eq(Array(joining), JOINING, "the graph is joined in two places: %s" % [joining])


## Only the painter tells the widget which cables to draw.
##
## `connect_node` is GraphEdit's own way of drawing a cable. Called from anywhere
## else, it is a cable on screen that no statement in the file put there.
func test_only_the_painter_draws_cables() -> void:
	var sources: Dictionary[String, String] = ComposerSourceScan.sources()
	var drawing: Array[String] = []
	for at: String in sources:
		if at.ends_with("composer_painter.gd"):
			continue
		if sources[at].contains(A_DRAWN_CABLE):
			drawing.append(at.get_file())
	assert_eq(Array(drawing), [], "only the painter connects nodes: %s" % [drawing])
