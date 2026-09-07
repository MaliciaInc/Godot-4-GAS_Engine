## Compiling an ability: what is wrong with it, where, and whether it can run.
##
## Those were one question before, and being one was the problem. "Can the
## Composer draw this" and "is this ready to run" have different answers all the
## time - an ability half written is drawable and not ready, one with a loop in
## it is ready and only partly drawable - so a single verdict forced one of them
## to be reported as the other.
##
## And a finding needs a place. A message on its own sends a person hunting
## through their own file for the line the tool meant, which is the moment they
## stop reading the messages. So every finding carries the file, the line, the
## column and the card it is about, and a code that outlives the wording.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const PluginWiring = preload("res://test/fixtures/plugin_wiring.gd")

const PATH: String = "res://abilities/compiled.gd"

## Whole and correct: nothing to say about it.
const READY: String = """extends GameplayAbility


func _activate_ability() -> bool:
	commit_ability()
	return true
"""

## A call short of a required argument, which does not compile.
const SHORT: String = """extends GameplayAbility


func _activate_ability() -> bool:
	add_tag()
	return true
"""

## Drawable in every part but one, and that part is left alone.
const WITH_A_LOOP: String = """extends GameplayAbility


func _activate_ability() -> bool:
	for target: Node in targets:
		end_ability()
	return true
"""

## Nothing to draw at all.
const NO_ENTRY: String = """extends GameplayAbility


func _something_else() -> bool:
	return true
"""


#region Getting there
func _compiled(source: String) -> GameplayCompileService.Result:
	return GameplayCompileService.compile(source, PATH)


func _first(result: GameplayCompileService.Result) -> GameplayCompileDiagnostic:
	return result.diagnostics[0] if not result.diagnostics.is_empty() else null
#endregion


#region Ready, or not, and why
## An ability with nothing wrong with it is ready, and says nothing.
func test_an_ability_with_nothing_wrong_is_ready_to_run() -> void:
	var result: GameplayCompileService.Result = _compiled(READY)

	assert_true(result.ready_to_run, "ready")
	assert_eq(result.diagnostics.size(), 0, "with nothing to say")


## The four states, and what each of them means for running it.
##
## One table because the point is exactly the difference between them: a
## warning does not stop a run and an error does, and a verdict that treated
## the two alike would refuse to run an ability whose only fault is a loop the
## tool will not touch.
##
##     [what it is, the source, is it ready, the code it reports]
func _abilities() -> Array:
	return [
		["nothing wrong", READY, true, &""],
		["a call short of an argument", SHORT, false, GameplayCompileDiagnostic.MISSING_ARGUMENT],
		["a region left alone", WITH_A_LOOP, true, GameplayCompileDiagnostic.KEPT_REGION],
		["nothing to draw", NO_ENTRY, false, GameplayCompileDiagnostic.NOT_DRAWABLE],
	]


func test_what_stops_an_ability_running_and_what_does_not() -> void:
	var rows: Array = _abilities()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var source: String = row[1]
		var ready: bool = row[2]
		var code: StringName = row[3]

		var result: GameplayCompileService.Result = _compiled(source)

		assert_eq(result.ready_to_run, ready, "%s: ready to run?" % described)
		if code != &"":
			assert_true(result.has(code), "%s: reports %s" % [described, code])
		checked += 1
	assert_eq(checked, rows.size(), "every state was offered")


## A draft that does not compile is still a draft: it is read, it is drawn, and
## what is wrong with it is said rather than hidden behind a refusal to look.
func test_a_draft_that_does_not_compile_is_still_read_and_still_says_why() -> void:
	var result: GameplayCompileService.Result = _compiled(SHORT)

	assert_false(result.ready_to_run, "not ready")
	assert_eq(result.errors().size(), 1, "one thing stops it")
	assert_eq(result.source_path, PATH, "and it knows which file it is about")
#endregion


#region A finding is a place
## Every part of where: the file, the line, the column, and the card.
func test_a_finding_carries_every_way_of_going_to_it() -> void:
	var found: GameplayCompileDiagnostic = _first(_compiled(SHORT))

	assert_eq(found.source_path, PATH, "which file")
	assert_eq(found.line, 5, "which line")
	assert_eq(found.column, 2, "and which column, past the indent")
	assert_false(found.node_id.is_empty(), "and which card")


## The column is where the statement starts, not where the line does.
##
## An editor taken to column one puts the caret in front of the indentation,
## which is not where anybody was looking.
func test_the_column_is_past_the_indent() -> void:
	var deeper: String = READY.replace(
		"	commit_ability()", "	if true:\n		add_tag()"
	)

	var found: GameplayCompileDiagnostic = _first(_compiled(deeper))

	assert_not_null(found, "it found the call short of an argument")
	assert_eq(found.column, 3, "two tabs in, so the third column")


## `file.gd:5:2`, the shape every editor lets you click.
func test_a_finding_says_where_it_is_in_the_shape_editors_take() -> void:
	var found: GameplayCompileDiagnostic = _first(_compiled(SHORT))

	assert_eq(found.at(), "compiled.gd:5:2", "file, line, column")


## A finding about the file rather than about anything in it has no line, and
## says so rather than pointing at line one.
func test_a_finding_about_the_file_points_at_no_line() -> void:
	var found: GameplayCompileDiagnostic = _first(_compiled(NO_ENTRY))

	assert_eq(found.line, 0, "there is no line to be at")
	assert_eq(found.at(), "compiled.gd", "so it names the file and stops")
	assert_true(found.node_id.is_empty(), "and no card either")
#endregion


#region Codes outlive wording
## Two abilities wrong in the same way report the same code, whatever the
## sentence says about either.
func test_the_same_kind_of_mistake_reports_the_same_code() -> void:
	var one: String = READY.replace("	commit_ability()", "	add_tag()")
	var other: String = READY.replace("	commit_ability()", "	remove_tag()")

	var first: GameplayCompileDiagnostic = _first(_compiled(one))
	var second: GameplayCompileDiagnostic = _first(_compiled(other))

	assert_eq(first.code, GameplayCompileDiagnostic.MISSING_ARGUMENT, "the same kind")
	assert_eq(second.code, first.code, "reported the same way")
	assert_ne(first.message, second.message, "while the sentences differ")


## A warning and an error are told apart by what they do, not by their wording.
func test_a_warning_does_not_stop_a_run_and_an_error_does() -> void:
	var warning: GameplayCompileDiagnostic = _first(_compiled(WITH_A_LOOP))
	var error: GameplayCompileDiagnostic = _first(_compiled(SHORT))

	assert_false(warning.stops_a_run(), "a kept region is not a fault")
	assert_true(error.stops_a_run(), "a call that will not compile is")


## The plugin takes the script editor to the line, which only a plugin can do.
##
## Asserted against its source, for the reason test_effect_asset_authoring.gd
## gives: an EditorPlugin refuses to be built outside the editor, so nothing
## headless can watch it wire anything. What this catches is the wiring going
## missing - which is how the line half of a place got dropped in the first
## place.
const WIRED: Array = [
	["the screen says where to go", "_composer_instance.go_to_line.connect(_on_go_to_line)"],
	["and the plugin takes the editor there", "EditorInterface.edit_script(script, line - 1)"],
	["a finding with no line takes nobody anywhere", "if line <= 0 or _composer_instance == null:"],
]


func test_the_plugin_takes_the_editor_to_the_line() -> void:
	assert_eq(
		PluginWiring.missing(WIRED), [] as Array[String], "every part of it is there"
	)


## Nothing at all is answered rather than crashed on.
func test_a_graph_that_is_not_there_is_answered() -> void:
	var result: GameplayCompileService.Result = GameplayCompileService.of_graph(null, "")

	assert_false(result.ready_to_run, "nothing is not ready")
	assert_eq(result.diagnostics.size(), 1, "and it says so once")
#endregion
