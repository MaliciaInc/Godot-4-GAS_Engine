## The two gates the plan declares, asked of the code rather than asserted in a
## document.
##
## Every line of PROJECTION_STABLE and VOCABULARY_STABLE is a claim someone can
## check, and a claim nobody checks is a sentence. These are the ones that were
## still only sentences: the properties that have to hold for every file rather
## than for the one a test happened to pick, and the promise that the catalog
## covers the engine rather than whatever somebody remembered to list.
##
## @meta_license: GAS_Engine Community Use License 1.0
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
		assert_eq(ComposerProjection.statements(graph).size(), 0, "%s drew nothing" % path.get_file())
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

		assert_eq(ComposerProjection.statements(graph).size(), 1, "%s drew one node: %s" % [entry.type_id, written])
		assert_eq(
			ComposerProjection.statements(graph)[0].type_id, entry.type_id, "%s read back as itself" % entry.type_id
		)
		assert_eq(
			ComposerProjection.statements(graph)[0].fields.size(), entry.parameters.size(),
			"%s kept all its arguments" % entry.type_id
		)


## The statement a node prints when every argument is filled in.
func _statement_for(entry: ComposerCatalog.Entry) -> String:
	var given: PackedStringArray = PackedStringArray()
	for position: int in entry.parameters.size():
		given.append("value_%d" % position)
	return "	%s(%s)" % [entry.type_id, ", ".join(given)]
#endregion


#region COMPOSER_STABLE
const SCRATCH: String = "user://composer_stable_%d.gd"
const AN_ABILITY: String = """extends GameplayAbility

@export var burning: GameplayEffect


func _activate_ability() -> bool:
	var level: float = get_ability_level()
	owner_asc.apply_gameplay_effect(burning, owner_asc, level)
	end_ability()
	return true
"""


func _laid_out(source: String, path: String) -> Dictionary[StringName, Vector2i]:
	return ComposerLayout.arrange(ComposerReader.read(source, path))


## The same file draws the same way twice.
##
## The layout is worked out again on every open - there is nowhere it could be
## remembered - so it has to land in the same place, or a person's graph
## rearranges itself between one look and the next for no reason they can see.
func test_the_same_file_draws_the_same_way_on_two_openings() -> void:
	for name: String in REPRESENTABLE:
		var path: String = REFERENCE % name
		var source: String = FileAccess.get_file_as_string(path)

		assert_eq(
			_laid_out(source, path), _laid_out(source, path),
			"%s lands where it landed" % name
		)


## Adding a statement at the end does not move what was already there.
##
## The thing that makes a graph worth looking at twice. A layout that reshuffles
## on every addition is one nobody builds a mental picture of.
func test_adding_a_statement_at_the_end_moves_nothing_that_was_there() -> void:
	var path: String = REFERENCE % "timed_buff"
	var source: String = FileAccess.get_file_as_string(path)
	var before: Dictionary[StringName, Vector2i] = _laid_out(source, path)

	var lines: PackedStringArray = source.split("
")
	var body: ComposerSpan = ComposerSubset.body_span(lines)
	var after: Dictionary[StringName, Vector2i] = _laid_out(
		ComposerEdits.insert_after(source, body.last_line, "	abort_ability()"), path
	)

	for id: StringName in before:
		assert_true(after.has(id), "%s is still drawn" % id)
		var moved: Vector2i = after[id]
		assert_eq(moved, before[id], "%s did not move" % id)


## Opening, editing and saving leaves a file GDScript can still compile.
##
## Not "reads back as the same graph" - loaded. The Composer writing something
## that parses in its own reader but not in Godot would be a tool that quietly
## breaks the build.
func test_opening_editing_and_saving_leaves_the_file_compiling() -> void:
	var path: String = SCRATCH % 1
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(AN_ABILITY)
	out.close()

	var doc: ComposerDocument = ComposerDocument.new()
	doc.open(AN_ABILITY, path)
	var node: ComposerNode = ComposerProjection.statements(doc.graph())[1]
	node.fields[0].display = "freezing"
	node.dirty = true
	var printed: ComposerWriter.Result = ComposerWriter.apply(
		doc.graph(), doc.printed(), false
	)
	assert_null(doc.commit(printed.text), "the edit was taken")
	assert_null(doc.save(), "and saved")

	assert_true(
		FileAccess.get_file_as_string(path).contains("freezing"), "the edit is on disk"
	)
	assert_not_null(load(path) as GDScript, "and Godot still compiles it")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Nothing undo or redo can reach is something the writer would refuse.
##
## Every text in the history was accepted by the same door, so this should hold
## by construction - which is exactly why it is worth checking: a claim that
## holds by construction is one nobody notices breaking.
func test_nothing_in_the_history_is_a_graph_the_writer_would_refuse() -> void:
	var path: String = SCRATCH % 2
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	out.store_string(AN_ABILITY)
	out.close()

	var doc: ComposerDocument = ComposerDocument.new()
	doc.open(AN_ABILITY, path)
	var body: ComposerSpan = ComposerSubset.body_span(doc.printed().split("
"))
	doc.insert("	abort_ability()", body.last_line)
	doc.remove([ComposerProjection.statements(doc.graph())[0].span] as Array[ComposerSpan])

	for _step: int in 3:
		doc.undo()
		_assert_writable(doc)
	for _step: int in 3:
		doc.redo()
		_assert_writable(doc)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _assert_writable(doc: ComposerDocument) -> void:
	var printed: ComposerWriter.Result = ComposerWriter.apply(doc.graph(), doc.printed())
	assert_true(printed.is_ok(), "the writer takes it: %s" % [
		printed.refusal.message if printed.refusal != null else ""
	])
	assert_eq(printed.text, doc.printed(), "and prints it back unchanged")


## The Composer never reaches a running game.
##
## Not a promise about export filters, which belong to whoever ships the game -
## a fact about this addon: nothing outside the editor folder names anything
## inside it, so there is no path by which a running game loads any of it.
func test_nothing_in_the_runtime_names_anything_in_the_editor() -> void:
	var editor_classes: Array[String] = []
	for described: Dictionary in ProjectSettings.get_global_class_list():
		var declared: String = described["class"]
		var where: String = described["path"]
		if where.begins_with("res://addons/GAS_Engine/editor/"):
			editor_classes.append(declared)
	assert_gt(editor_classes.size(), 10, "there is an editor to keep out")

	for described: Dictionary in ProjectSettings.get_global_class_list():
		var where: String = described["path"]
		if not where.begins_with("res://addons/GAS_Engine/") or where.contains("/editor/"):
			continue
		var source: String = FileAccess.get_file_as_string(where)
		for declared: String in editor_classes:
			assert_false(
				_uses(source, declared),
				"%s does not reach %s" % [where.get_file(), declared]
			)


## Named as code rather than mentioned in a comment.
static func _uses(source: String, declared: String) -> bool:
	for line: String in source.split("
"):
		if line.strip_edges().begins_with("#"):
			continue
		if line.contains(declared):
			return true
	return false
#endregion
