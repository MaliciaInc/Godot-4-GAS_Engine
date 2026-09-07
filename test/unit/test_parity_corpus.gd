## The differential corpus, run.
##
## Every case is a statement about what the reference engine does, checked in
## all eleven dimensions at once - attributes, tags, effects, signals, the order
## of two of them, handle identity and what a person can author. A case that
## agreed on the numbers while firing the wrong signals in the wrong order and
## minting a new handle each time would be a case that passed and a parity claim
## that was false.
##
## The results are written where a person can read them afterwards, because a
## corpus that only ever says PASS is a corpus nobody can review.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const HEALTH: StringName = &"health"

const RESULTS: String = "res://artifacts/parity/results"
const RESULTS_FILE: String = RESULTS + "/corpus.md"

const HEADER: String = (
	"# Differential corpus results\n"
	+ "\n"
	+ "Written by `test/unit/test_parity_corpus.gd` on every suite run. Machine\n"
	+ "output: what is committed is the corpus and the runner, not this.\n"
	+ "\n"
)


func test_the_corpus_has_cases_and_every_one_of_them_says_all_eleven_things() -> void:
	var cases: Array[GameplayParityCase] = GameplayParityContracts.all()

	assert_gt(cases.size(), 0, "there is a corpus at all")
	var incomplete: Array[StringName] = []
	for case: GameplayParityCase in cases:
		if not case.is_complete():
			incomplete.append(case.id)
	assert_eq(
		incomplete, [] as Array[StringName],
		"a case that forgot half of itself passes for the wrong reason"
	)


## Every case stamped with the reference it was taken from.
##
## Per case rather than per corpus: a case revised against a later reference has
## to say so, and one version at the top of the file would hide it.
func test_every_case_names_the_reference_it_was_taken_from() -> void:
	for case: GameplayParityCase in GameplayParityContracts.all():
		assert_false(
			case.reference_version.is_empty(), "%s says which reference" % case.id
		)


func test_godot_agrees_with_the_reference_on_every_case() -> void:
	var cases: Array[GameplayParityCase] = GameplayParityContracts.all()
	var lines: Array[String] = []
	var disagreed: Array[String] = []

	for case: GameplayParityCase in cases:
		var result: GameplayParityResult = GameplayParityRunner.run(case, self)
		lines.append(result.to_line())
		if not result.agrees():
			disagreed.append(result.to_line())

	_write(lines)
	assert_eq(disagreed, [] as Array[String], "every case agrees")
	assert_eq(lines.size(), cases.size(), "and every case was actually run")


## The results, where somebody can read them.
##
## Best effort: a checkout whose artifacts directory cannot be written to is a
## checkout that still runs its suite, and failing the corpus because a file
## could not be opened would be reporting the wrong thing.
func _write(lines: Array[String]) -> void:
	DirAccess.make_dir_recursive_absolute(RESULTS)
	var file: FileAccess = FileAccess.open(RESULTS_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(HEADER + "\n".join(lines) + "\n")
	file.close()


#region The checker is checked
## A corpus is only worth what its runner notices.
##
## Every dimension is claimed wrongly here, one at a time, against a case whose
## input does nothing at all - so what is being asserted is that the runner
## reports the disagreement, and in which dimension. A runner that quietly
## agreed with everything would make a green corpus meaningless, and nothing
## else in this file would say so.
##
##     [what is claimed wrongly, how to spoil the case, what should be reported]
func _spoiled() -> Array:
	return [
		[
			"an attribute that is not what it says",
			func(case: GameplayParityCase) -> void: case.expected_attributes = {HEALTH: 1.0},
			"attribute",
		],
		[
			"a tag that is not held",
			func(case: GameplayParityCase) -> void: case.expected_tags = {&"Never.Held": 3},
			"tag",
		],
		[
			"effects that are not running",
			func(case: GameplayParityCase) -> void: case.expected_effects = 4,
			"effects are running",
		],
		[
			"a signal that never fired",
			func(case: GameplayParityCase) -> void:
				case.expected_signals = [&"cue_executed"] as Array[StringName],
			"never fired",
		],
		[
			"an order nothing happened in",
			func(case: GameplayParityCase) -> void:
				case.expected_order = [&"active_effect_added"] as Array[StringName],
			"did not fire after",
		],
		[
			"an identity rule nobody knows",
			func(case: GameplayParityCase) -> void: case.expected_identity = &"invented",
			"identity rule",
		],
		[
			"an operation nobody can author",
			func(case: GameplayParityCase) -> void:
				case.expected_authoring = &"no_such_operation",
			"not on the palette",
		],
	]


func test_the_runner_reports_a_disagreement_in_every_dimension() -> void:
	var rows: Array = _spoiled()
	var checked: int = 0
	for row: Array in rows:
		var described: String = row[0]
		var spoil: Callable = row[1]
		var reported: String = row[2]

		var case: GameplayParityCase = _a_case_that_does_nothing()
		spoil.call(case)
		var result: GameplayParityResult = GameplayParityRunner.run(case, self)

		assert_false(result.agrees(), described)
		assert_string_contains(
			"; ".join(result.disagreements), reported, "%s: reported as itself" % described
		)
		checked += 1
	assert_eq(checked, rows.size(), "every dimension was spoiled")


## And a case that forgot half of itself is reported as incomplete rather than
## run and agreed with.
func test_a_case_that_does_not_say_all_eleven_things_is_refused() -> void:
	var half: GameplayParityCase = GameplayParityCase.new()
	half.id = &"half.a.case"

	var result: GameplayParityResult = GameplayParityRunner.run(half, self)

	assert_false(result.agrees())
	assert_string_contains("; ".join(result.disagreements), "eleven things")


## A case that claims exactly what a character with nothing done to it is.
func _a_case_that_does_nothing() -> GameplayParityCase:
	var case: GameplayParityCase = GameplayParityCase.new()
	case.id = &"nothing.happens"
	case.attributes = {HEALTH: 100.0}
	case.input = func(_fixture: ASCFixture) -> void: pass
	case.expected_attributes = {HEALTH: 100.0}
	case.expected_effects = 0
	case.expected_identity = &"no_handles"
	case.expected_authoring = GameplayParityRunner.ENGINE_PLUMBING
	return case
#endregion
