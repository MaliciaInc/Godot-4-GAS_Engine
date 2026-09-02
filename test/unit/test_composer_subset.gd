## The subset: what the Composer can draw, and what it refuses to touch.
##
## The tests that matter are not the ones proving a call is a call. They are the
## ones proving that nothing slips through unclassified, and that a refusal
## names a line - because a reader that quietly skips what it does not
## understand builds a graph that looks complete, and the writer then deletes
## the skipped line from the file.
##
## @meta_license: MIT
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
## `apply(build())` is refused because a node draws one operation - drawing two
## as one makes the canvas a summary of the code instead of a view of it. An
## untyped local is refused because the graph shows a port's type, and inferring
## it would let the canvas and the file disagree until someone runs the game.
func test_the_boundary_of_what_can_be_drawn() -> void:
	var boundaries: Array[Array] = [
		["apply_effect(build_spec())", "apply_effect(spec, 1.0)", "one node, one operation"],
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
