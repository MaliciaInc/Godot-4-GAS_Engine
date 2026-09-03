## The subset: what the Composer can draw, and what it refuses to touch.
##
## The tests that matter are not the ones proving a call is a call. They are the
## ones proving that nothing slips through unclassified, and that a refusal
## names a line - because a reader that quietly skips what it does not
## understand builds a graph that looks complete, and the writer then deletes
## the skipped line from the file.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const ENTRY: String = "func _activate_ability() -> void:"


func _body(statements: Array) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("extends GameplayAbility")
	lines.append("")
	lines.append(ENTRY)
	for statement: String in statements:
		lines.append("\t" + statement)
	return lines


func _kind(line: String) -> ComposerSubset.Kind:
	return ComposerSubset.classify(line).kind


#region Every line is decided
## There is no "I do not know". The value of that is the failure it prevents:
## a line nobody classified is a line nobody draws and the writer does not
## reprint.
func test_no_line_is_left_unclassified() -> void:
	var lines: Array[String] = [
		"", "\t", "# a note", "commit_ability()", "var x: int = 1", "await wait_delay(1.0)",
		"if ready:", "else:", "return", "super()", "match mode:", "Mode.FAST:",
		"for i in 3:", "%%%",
	]
	for line: String in lines:
		var verdict: ComposerSubset.Verdict = ComposerSubset.classify(line)
		var named: bool = verdict.is_representable() or not verdict.reason.is_empty()
		assert_true(named, "'%s' was decided one way or the other" % line)


func test_the_shapes_the_subset_admits() -> void:
	assert_eq(_kind("commit_ability()"), ComposerSubset.Kind.CALL, "a bare call")
	assert_eq(_kind("var level: float = 1.0"), ComposerSubset.Kind.LOCAL, "a typed local")
	assert_eq(_kind("await wait_target_data()"), ComposerSubset.Kind.AWAIT, "an await")
	assert_eq(_kind("if is_ready:"), ComposerSubset.Kind.BRANCH, "a branch")
	assert_eq(_kind("else:"), ComposerSubset.Kind.BRANCH_ELSE, "its other side")
	assert_eq(_kind("elif late:"), ComposerSubset.Kind.BRANCH_ELSE, "and its middle")
	assert_eq(_kind("return"), ComposerSubset.Kind.RETURN, "a return")
	assert_eq(_kind("super()"), ComposerSubset.Kind.SUPER, "a super call")
	assert_eq(_kind("match policy:"), ComposerSubset.Kind.MATCH, "a match")
	assert_eq(_kind("Policy.INSTANT:"), ComposerSubset.Kind.MATCH_CASE, "one of its arms")
	assert_eq(_kind("_:"), ComposerSubset.Kind.MATCH_CASE, "including the last")
#endregion


#region What it refuses, and why
## A refusal names the construction rather than scolding the file. The file is
## fine; this tool cannot draw it.
func test_a_loop_is_refused_by_name() -> void:
	var verdict: ComposerSubset.Verdict = ComposerSubset.classify("for target in targets:")

	assert_false(verdict.is_representable(), "a loop has no single place on a canvas")
	assert_true(verdict.reason.contains("loop"), "and the reason says so: %s" % verdict.reason)


func test_an_inline_function_is_refused() -> void:
	var verdict: ComposerSubset.Verdict = ComposerSubset.classify(
		"var done: Callable = func(): pass"
	)
	assert_false(verdict.is_representable(), "a lambda is code the graph cannot show")


## Where the subset ends, stated as pairs.
##
## Each row is a construction this refuses beside the nearest one it admits.
## Written as two tests they were the same eight lines twice; written as a table
## the boundary is the content rather than something a reader infers from two
## examples that happen to sit near each other.
##
## Two calls standing side by side are refused because neither is the statement:
## `open() + shut()` has no single thing a node could be named after. A call
## *inside* an argument list is a different case and is admitted - see below. An
## untyped local is refused because the graph shows a port's type, and inferring
## it would let the canvas and the file disagree until someone runs the game.
func test_the_boundary_of_what_can_be_drawn() -> void:
	var boundaries: Array[Array] = [
		["open_gate() + shut_gate()", "open_gate()", "a statement is one call"],
		["var level := 1.0", "var level: float = 1.0", "a written type or nothing"],
		["var level = 1.0", "var level: float = 1.0", "a written type or nothing"],
	]

	for row: Array in boundaries:
		var refused: String = row[0]
		var admitted: String = row[1]
		var why: String = row[2]
		assert_false(
			ComposerSubset.classify(refused).is_representable(),
			"%s: '%s' is outside" % [why, refused]
		)
		assert_true(
			ComposerSubset.classify(admitted).is_representable(),
			"%s: '%s' is inside" % [why, admitted]
		)


## A call inside an argument list is kept as the text it is.
##
## This was refused once, on the grounds that a node draws one operation. The
## rule did not survive contact with real abilities: `apply(effect, asc,
## get_ability_level())` is not exotic, it is most of them, and refusing it
## turned away whole files. Nor was the rule ever really applied - `level + 1.0`
## in an argument is an operation too, and was always admitted.
##
## What the check was actually protecting was the comma: splitting arguments on
## every one of them cuts `build(x, y)` in half. Counting brackets instead costs
## one scan, and the inner call reaches the card as the text a person wrote and
## is printed back unchanged.
func test_a_call_inside_an_argument_is_part_of_the_argument() -> void:
	var written: String = "apply_effect(damage, owner_asc, get_ability_level())"

	assert_true(
		ComposerSubset.classify(written).is_representable(), "the statement is one call"
	)
	assert_eq(
		ComposerSubset.arguments_of("damage, owner_asc, get_ability_level()").size(), 3,
		"and its arguments are its own, not the inner call's"
	)


## A comma inside a string is a character, not a boundary.
func test_a_comma_inside_a_string_does_not_split_an_argument() -> void:
	assert_eq(
		ComposerSubset.arguments_of("\"a, b\", second").size(), 2, "two arguments, not three"
	)


## A statement whose brackets have not closed runs on into the line below it.
## Anything that reads a body has to agree about that, or a wrapped call is a
## statement to one of them and a stray fragment to the other.
func test_a_statement_can_span_the_lines_it_was_wrapped_across() -> void:
	var lines: PackedStringArray = PackedStringArray([
		"func _activate_ability() -> void:",
		"\tvar found: GameplayAbilityTargetData = GameplayTargetingService.overlap_2d(",
		"\t\towner_asc, world, sweep",
		"\t)",
		"\tend_ability()",
	])
	var body: ComposerSpan = ComposerSubset.body_span(lines)

	var found: Array[ComposerSubset.Statement] = ComposerSubset.statements(lines, body)

	assert_eq(found.size(), 2, "two statements, not four lines")
	assert_eq(found[0].first, 2, "the first starts where it was written")
	assert_eq(found[0].last, 4, "and ends where its brackets close")
	assert_eq(found[0].verdict.kind, ComposerSubset.Kind.LOCAL, "and it is a local")
	assert_null(
		ComposerSubset.first_refusal(lines, body),
		"and nothing refuses the file for being formatted"
	)


## Setting a property is a statement people write constantly. Refusing it made
## the Composer unable to open an ability that configured anything before using
## it, which is most of them.
func test_an_assignment_is_a_statement() -> void:
	var assignments: Array[String] = [
		"sweep.radius = radius",
		"sweep.center = caster.global_position",
		"charges = charges - 1",
		"charges += 1",
	]

	for written: String in assignments:
		var verdict: ComposerSubset.Verdict = ComposerSubset.classify(written)
		assert_eq(verdict.kind, ComposerSubset.Kind.ASSIGN, "assigns: %s" % written)


## A comparison is not an assignment. Reading one as the other would turn a
## branch's condition into a statement that sets something.
func test_a_comparison_is_not_an_assignment() -> void:
	var comparisons: Array[String] = [
		"if charges == 0:",
		"if charges != 0:",
		"if charges <= 0:",
		"if charges >= 0:",
	]

	for written: String in comparisons:
		assert_eq(
			ComposerSubset.classify(written).kind, ComposerSubset.Kind.BRANCH,
			"a branch, not an assignment: %s" % written
		)
#endregion


#region Finding the body
## The writer's whole promise rests on this: outside the range, the file is not
## touched.
func test_the_body_is_the_lines_inside_the_entry_point() -> void:
	var lines: PackedStringArray = _body(["commit_ability()", "end_ability()"])
	var span: ComposerSpan = ComposerSubset.body_span(lines)

	assert_true(span.is_valid(), "it was found")
	assert_eq(span.first_line, 4, "the line after the signature")
	assert_eq(span.last_line, 5, "through the last indented one")


## Everything after the method belongs to the file, not to the graph.
func test_the_body_stops_where_the_indentation_does() -> void:
	var lines: PackedStringArray = _body(["commit_ability()"])
	lines.append("")
	lines.append("")
	lines.append("func _on_ended() -> void:")
	lines.append("\tpass")

	var span: ComposerSpan = ComposerSubset.body_span(lines)
	assert_eq(span.last_line, 4, "the helper below is not part of the graph")


func test_a_script_without_the_entry_point_has_no_body() -> void:
	var lines: PackedStringArray = PackedStringArray(["extends GameplayAbility", ""])
	assert_false(ComposerSubset.body_span(lines).is_valid(), "nothing to draw")
#endregion


#region Judging a whole body
func test_a_body_the_subset_admits_is_not_refused() -> void:
	var lines: PackedStringArray = _body([
		"commit_ability()",
		"var target: Node = await wait_target_data()",
		"# aim first",
		"apply_gameplay_effect(burning, 1.0)",
	])

	assert_null(
		ComposerSubset.first_refusal(lines, ComposerSubset.body_span(lines)),
		"every line is something this can draw"
	)


## The refusal carries the line, because a reason without a place sends someone
## hunting through a file for a construction they have to find themselves.
func test_a_refusal_names_the_line_it_happened_on() -> void:
	var lines: PackedStringArray = _body([
		"commit_ability()",
		"for target in targets:",
		"\tapply_gameplay_effect(burning, 1.0)",
	])

	var found: ComposerGraph.Diagnostic = ComposerSubset.first_refusal(
		lines, ComposerSubset.body_span(lines)
	)

	assert_not_null(found, "it refused")
	assert_eq(
		found.severity, ComposerGraph.Severity.NOT_REPRESENTABLE,
		"read-only, not broken: the file is fine"
	)
	assert_eq(found.span.first_line, 5, "the loop's own line")


func test_a_script_with_no_entry_point_is_refused_by_name() -> void:
	var lines: PackedStringArray = PackedStringArray(["extends GameplayAbility"])
	var found: ComposerGraph.Diagnostic = ComposerSubset.first_refusal(
		lines, ComposerSubset.body_span(lines)
	)

	assert_not_null(found, "there is nothing to open")
	assert_true(
		found.message.contains(ComposerSubset.ENTRY_POINT),
		"and it says which method it looked for: %s" % found.message
	)
#endregion
