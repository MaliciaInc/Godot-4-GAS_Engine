## The two gates the plan declares, asked of the code rather than asserted in a
## document.
##
## Every line of PROJECTION_STABLE and VOCABULARY_STABLE is a claim someone can
## check, and a claim nobody checks is a sentence. These are the ones that were
## still only sentences: the properties that have to hold for every file rather
## than for the one a test happened to pick, and the promise that the catalog
## covers the engine rather than whatever somebody remembered to list.
##
## @meta_license: MIT
extends GutTest

const REFERENCE: String = "res://addons/GAS_Engine/reference/%s.gd"
const REPRESENTABLE: Array[String] = [
	"instant_damage", "timed_buff", "sweeping_volley",
	"costly_strike", "confirmed_blast", "cued_dash",
]

## The one ability among the engine's own fixtures that is still outside the
## subset, and why it is only one.
##
## There were six when this was written. C10 widened the subset - a call in an
## argument list, a wrapped statement, an assignment - and five of them came
## inside. Checking the list instead of the files would have left a corpus that
## claimed to test refusals while testing nothing.
const OUTSIDE: Array[String] = [
	"res://test/fixtures/fireball_ability.gd",
]

## Things that are not an ability at all. The reader is handed each one and has
## to come back with a graph or a reason, never a crash.
const HOSTILE: Array[String] = [
	"",
	"\t",
	"func _activate_ability() -> void:",
	"extends GameplayAbility",
	"func _activate_ability() -> void:\n\t",
	"func _activate_ability() -> void:\n\tapply(",
	"func _activate_ability() -> void:\n\t)))",
	" ",
]


func _read(path: String) -> ComposerGraph:
	return ComposerReader.read(FileAccess.get_file_as_string(path), path)


#region PROJECTION_STABLE
## Read, write, read: the same graph.
##
## Checked by signature rather than by eye, and over every reference ability
## rather than one. A round trip that holds for the file somebody wrote the test
## against and drifts on the next one is not a property, it is a coincidence.
func test_reading_writing_and_reading_again_gives_the_same_graph() -> void:
	for name: String in REPRESENTABLE:
		var path: String = REFERENCE % name
		var source: String = FileAccess.get_file_as_string(path)
		var first: ComposerGraph = ComposerReader.read(source, path)

		var written: ComposerWriter.Result = ComposerWriter.apply(first, source)
		var second: ComposerGraph = ComposerReader.read(written.text, path)

		assert_eq(
			ComposerWriter.signature(second), ComposerWriter.signature(first),
			"%s came back as the graph it was" % name
		)


## Write, read, write: the same text.
##
## The other half. A save that is not idempotent turns every open-and-close into
## a diff somebody has to explain in review.
func test_writing_twice_without_editing_changes_nothing_the_second_time() -> void:
	for name: String in REPRESENTABLE:
		var path: String = REFERENCE % name
		var source: String = FileAccess.get_file_as_string(path)

		var once: ComposerWriter.Result = ComposerWriter.apply(
			ComposerReader.read(source, path), source
		)
		var twice: ComposerWriter.Result = ComposerWriter.apply(
			ComposerReader.read(once.text, path), once.text
		)

		assert_true(once.is_ok() and twice.is_ok(), "%s saved twice" % name)
		assert_eq(twice.text, once.text, "%s is the same text the second time" % name)


## A corpus of abilities the subset cannot draw, every one refused with a reason.
##
## The refusal has to name a line and say something, or a person is told their
## file cannot be drawn and left to work out which part of it.
func test_every_construction_the_subset_refuses_says_so_by_name() -> void:
	for rule: Array in ComposerSubset.REFUSED:
		var keyword: String = rule[0]
		var reason: String = rule[1]
		var source: String = (
			"extends GameplayAbility


func _activate_ability() -> void:
"
			+ "	" + keyword + "x:
		end_ability()
"
		)

		var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

		assert_false(graph.is_editable(), "%s is outside the subset" % keyword.strip_edges())
		assert_eq(graph.blocked_reason(), reason, "and says so in its own words")


## The corpus, checked against the files rather than against a memory of them.
func test_every_ability_outside_the_subset_is_refused_with_a_reason() -> void:
	for path: String in OUTSIDE:
		var graph: ComposerGraph = _read(path)

		assert_false(graph.is_editable(), "%s is outside the subset" % path.get_file())
		assert_eq(graph.nodes.size(), 0, "%s drew nothing" % path.get_file())
		assert_eq(graph.diagnostics.size(), 1, "%s said so once" % path.get_file())
		assert_eq(
			graph.diagnostics[0].severity, ComposerGraph.Severity.NOT_REPRESENTABLE,
			"%s: not an error in the file" % path.get_file()
		)
		assert_false(
			graph.diagnostics[0].message.is_empty(), "%s said why" % path.get_file()
		)
		assert_true(
			graph.diagnostics[0].span.is_valid(), "%s said where" % path.get_file()
		)


## The reader never throws. It comes back with a graph or with a reason.
##
## An editor panel that can be made to crash by a file somebody is halfway
## through typing is a panel that takes the editor with it.
func test_the_reader_answers_every_file_it_is_handed() -> void:
	for source: String in HOSTILE:
		var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

		assert_not_null(graph, "answered: %s" % source.c_escape())
		assert_true(
			graph.is_editable() or not graph.blocked_reason().is_empty(),
			"either drawable or refused with a reason: %s" % source.c_escape()
		)


## A file with nothing but a body still round-trips, and one whose body is empty
## is not mistaken for one that could not be read.
func test_an_empty_body_is_drawn_as_empty_rather_than_refused() -> void:
	var source: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n\tpass\n"
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_true(graph.is_editable(), "read: %s" % graph.blocked_reason())
	var saved: ComposerWriter.Result = ComposerWriter.apply(graph, source)
	assert_eq(saved.text, source, "and written back unchanged")
#endregion


#region VOCABULARY_STABLE
## The catalog covers the engine.
##
## The plan's claim, asked of the tree. Not "every method somebody remembered to
## list is there" - every public method the engine declares is a node, with no
## exceptions list to consult and none to keep true. A call added to the engine
## is on the palette; one renamed takes its node with it; one removed cannot
## linger, because there is nowhere for it to linger.
func test_every_public_method_of_every_source_is_offered() -> void:
	for declared: StringName in ComposerCatalog.SOURCES:
		var path: String = ComposerCatalog.script_for(declared)
		var script: GDScript = load(path) as GDScript
		for described: Dictionary in script.get_script_method_list():
			var name: String = described["name"]
			if name.begins_with("_") or name.begins_with("@"):
				continue
			assert_not_null(
				ComposerCatalog.find_on(path, StringName(name)),
				"%s.%s is offered" % [path.get_file(), name]
			)


## And nothing is offered that the engine does not declare.
func test_nothing_is_offered_that_the_engine_does_not_declare() -> void:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		var script: GDScript = load(entry.source) as GDScript
		var live: bool = false
		for described: Dictionary in script.get_script_method_list():
			var name: String = described["name"]
			if StringName(name) == entry.type_id:
				live = true
				break
		assert_true(live, "%s is still on %s" % [entry.type_id, entry.source.get_file()])


## Whether a call suspends is read off its return type, not off a list.
##
## A task is the thing an ability waits on, so a call that hands one back is a
## call that suspends. This was a written list for a while, and the list was
## wrong about one entry - the card said `await` over a call that does not wait.
func test_what_suspends_is_read_off_the_return_type() -> void:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		var script: GDScript = load(entry.source) as GDScript
		for described: Dictionary in script.get_script_method_list():
			var name: String = described["name"]
			if StringName(name) != entry.type_id:
				continue
			var returned: Dictionary = described["return"]
			var declared: String = returned["class_name"]
			assert_eq(
				entry.awaits,
				ComposerTypes.inherits(StringName(declared), &"GameplayAbilityTask"),
				"%s returns %s" % [entry.type_id, declared]
			)
			break


## Every node prints a statement that reads back as the same node.
##
## Stronger than "compiles", and checkable here: the printed line goes back
## through the reader and has to come out as the call it was. A node that prints
## something the reader reads as a different call is a node that rewrites
## somebody's ability into another one.
func test_every_offered_node_prints_a_statement_that_reads_back_as_itself() -> void:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		var written: String = _statement_for(entry)
		var source: String = (
			"extends GameplayAbility


func _activate_ability() -> void:
"
			+ written + "
"
		)
		var graph: ComposerGraph = ComposerReader.read(source, entry.source)

		assert_eq(graph.nodes.size(), 1, "%s drew one node: %s" % [entry.type_id, written])
		assert_eq(
			graph.nodes[0].type_id, entry.type_id, "%s read back as itself" % entry.type_id
		)
		assert_eq(
			graph.nodes[0].fields.size(), entry.parameters.size(),
			"%s kept all its arguments" % entry.type_id
		)


## The statement a node prints when every argument is filled in.
func _statement_for(entry: ComposerCatalog.Entry) -> String:
	var given: PackedStringArray = PackedStringArray()
	for position: int in entry.parameters.size():
		given.append("value_%d" % position)
	return "	%s(%s)" % [entry.type_id, ", ".join(given)]
#endregion
