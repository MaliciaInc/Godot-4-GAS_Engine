## A wait the Composer writes, and whether it waits.
##
## Every call that hands back an ability task was written as `await wait_delay(1.5)`,
## and every test that looked at it read the text and agreed. GDScript does not
## agree: an `await` on something that is neither a signal nor a coroutine takes
## the value and carries straight on, so the ability ran its whole body inside
## the call that started it and the wait was a word on a card. It was found by
## running what the Composer wrote inside a game, not by reading it.
##
## So the claim this file exists for is proved by running a body. The others are
## about what keeps that body waiting once somebody edits it, and about saying so
## when a file already holds a wait that does not.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")

const HEAD: String = "extends GameplayAbility\n\n\nfunc _activate_ability() -> bool:\n"
const PATH: String = "res://abilities/waits.gd"
const GAME_SCRIPT: String = "res://test/fixtures/game_composer_nodes.gd"
const SAVED: String = "user://composer_waits_ability.gd"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var document: ComposerDocument = null
var ops: ComposerStatementOps = null


func before_each() -> void:
	fixture = Fixture.create("Waiting")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	document = ComposerDocument.new()
	ops = ComposerStatementOps.new()
	ops.bind(document)


func after_each() -> void:
	ComposerCatalog.forget(ComposerCatalog.key_for(GAME_SCRIPT, &"play_flourish"))
	if FileAccess.file_exists(SAVED):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVED))
	fixture = null
	asc = null
	document = null
	ops = null


#region Getting there
func _open(statements: Array[String]) -> void:
	var body: String = ""
	for statement: String in statements:
		body += "\t" + statement + "\n"
	document.open(HEAD + body, PATH)


func _ability_key(method: StringName) -> StringName:
	return ComposerCatalog.key_for(
		ComposerCatalog.script_for(ComposerCatalog.ABILITY_CLASS), method
	)


func _first_statement() -> ComposerNode:
	return ComposerProjection.statements(document.graph())[0]


## The body the document holds, saved, loaded and granted to the fixture.
##
## Through a file rather than a script built in memory: an ability scene packed
## from a script with no path is not one any game has, and Godot says so while
## instantiating it.
func _granted_from_document() -> GameplayAbilitySpec:
	var file: FileAccess = FileAccess.open(SAVED, FileAccess.WRITE)
	file.store_string(document.printed())
	file.close()
	var script: GDScript = ResourceLoader.load(SAVED, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	assert_true(script != null and script.can_instantiate(), "what the Composer wrote compiles")
	var made: Object = script.new()
	return AbilityFactory.give(asc, made as GameplayAbility)


func _waits_that_do_not(graph: ComposerGraph) -> Array[ComposerGraph.Diagnostic]:
	var found: Array[ComposerGraph.Diagnostic] = []
	for entry: ComposerGraph.Diagnostic in graph.diagnostics:
		if entry.code == GameplayCompileDiagnostic.AWAIT_WITHOUT_WAITING:
			found.append(entry)
	return found
#endregion


#region A wait that waits
## The palette's wait, given a second in the Inspector, holds the ability open
## for that second and not a frame less.
func test_a_wait_put_down_from_the_palette_holds_the_ability_until_it_is_over() -> void:
	_open(["return true"] as Array[String])
	assert_null(ops.insert_call([] as Array[StringName], _ability_key(&"wait_delay")), "the wait was added")
	assert_null(
		document.commit(document.printed().replace("wait_delay(0.0)", "wait_delay(1.0)")),
		"and given a second"
	)

	var spec: GameplayAbilitySpec = _granted_from_document()
	assert_not_null(spec, "granted")
	var ability: GameplayAbility = spec.per_actor_instance
	assert_true(asc.ability_runtime.try_activate(spec.handle).is_ok(), "it starts")
	assert_true(ability.is_active, "and is still waiting when the call that started it returns")

	asc._process(0.4)
	assert_true(ability.is_active, "part of the second is not all of it")
	asc._process(0.6)
	assert_false(ability.is_active, "and once the second is over, so is the ability")
#endregion


#region Keeping it waiting
func test_a_one_line_wait_reads_its_own_argument_and_not_the_rest_of_the_line() -> void:
	_open(["await wait_delay(0.5).completed()", "return true"] as Array[String])
	var wait: ComposerNode = _first_statement()

	assert_eq(wait.type_id, &"wait_delay", "the card is the wait")
	assert_eq(wait.fields.size(), 1, "with one argument")
	assert_eq(wait.fields[0].display, "0.5", "and it is the number, not the tail of the line")
	assert_true(_waits_that_do_not(document.graph()).is_empty(), "and nothing to say about it")


## Whichever form the wait was in, editing its number writes one that waits - so
## editing a wait written before this is also its repair.
func test_editing_a_wait_s_seconds_writes_a_wait_that_waits_whatever_it_was_before() -> void:
	var overrides: Dictionary[int, String] = {0: "1.5"}
	for before: String in ["await wait_delay(0.5).completed()", "await wait_delay(0.5)"]:
		_open([before, "return true"] as Array[String])

		assert_eq(
			ComposerWriter.render_with_field_overrides(_first_statement(), overrides),
			"\tawait wait_delay(1.5).completed()",
			"edited from: %s" % before
		)


## An await on the task's own signal does wait, and is left alone.
func test_an_await_on_the_task_s_signal_is_not_said_to_be_wrong() -> void:
	_open(["await wait_target_data().finished", "return true"] as Array[String])

	assert_true(_waits_that_do_not(document.graph()).is_empty(), "it waits")
#endregion


#region Saying so about a wait that does not
## A file written before this still opens, draws and saves - and says, where the
## person is looking, that this line waits on nothing.
func test_an_await_on_the_call_itself_is_said_not_to_wait() -> void:
	_open(["await wait_delay(0.5)", "return true"] as Array[String])
	var found: Array[ComposerGraph.Diagnostic] = _waits_that_do_not(document.graph())

	assert_eq(found.size(), 1, "one finding")
	assert_eq(found[0].severity, ComposerGraph.Severity.WARNING, "a warning, because the file still runs")
	assert_eq(found[0].node_id, _first_statement().id, "on the wait's own card")
	assert_true(document.graph().is_editable(), "and it can still be edited")


## Bound to a local, the line waits on nothing and holds the task rather than
## what the task found.
func test_an_await_bound_to_a_local_is_said_not_to_wait_either() -> void:
	_open([
		"var target: GameplayAbilityTargetData = await wait_target_data()",
		"return true",
	] as Array[String])

	assert_eq(_waits_that_do_not(document.graph()).size(), 1, "one finding")
#endregion


#region A game's own calls
## A call a game registers as suspending is a coroutine of its own, not a task.
## It is awaited as written, and not told it is wrong for it.
func test_a_game_s_own_suspending_call_is_awaited_as_it_is_written() -> void:
	assert_eq(ComposerCatalog.register("play_flourish", &"Flourish", GAME_SCRIPT, true), "", "registered")
	var written: String = ComposerStatementFactory.call_statement(
		ComposerCatalog.find_on(GAME_SCRIPT, &"play_flourish"), PATH
	)

	assert_true(written.contains("await ") and written.contains("play_flourish("), "awaited: %s" % written)
	assert_false(written.contains(".completed()"), "and not as a task: %s" % written)
#endregion
