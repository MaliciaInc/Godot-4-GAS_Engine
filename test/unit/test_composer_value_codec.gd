## Values into source, and source back into values.
##
## The codec is what lets a control edit an argument without the control and the
## file drifting apart, so the tests that matter are the round trips and the
## refusals. A refusal is not a gap: it is the codec saying "this is an
## expression somebody wrote", which is how `pick.target_data` keeps being text
## a person can edit instead of becoming a spinner showing zero.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const OK: String = ComposerValueCodec.OK
const VALUE: String = ComposerValueCodec.VALUE


## GUT's assertions take Variant, and a Dictionary lookup is a Variant of
## inferred type - which the strict-typing settings refuse to pass. Named here
## once so the tests below read as what they check rather than as ceremony.
func _ok(read: Dictionary) -> bool:
	var found: bool = read[OK]
	return found


func _value(read: Dictionary) -> Variant:
	var found: Variant = read[VALUE]
	return found


#region Round trips
## Written and read again is the value it was, for every literal type the matrix
## promises a control for.
func test_every_literal_type_survives_being_written_and_read() -> void:
	var cases: Array = [
		[true, &"bool", "true"],
		[false, &"bool", "false"],
		[7, &"int", "7"],
		[1.5, &"float", "1.5"],
		["a word", &"String", "\"a word\""],
		[&"Status.Burning", &"StringName", "&\"Status.Burning\""],
		[NodePath("../Body"), &"NodePath", "^\"../Body\""],
		[Vector2(1.0, 2.0), &"Vector2", "Vector2(1.0, 2.0)"],
		[Vector2i(1, 2), &"Vector2i", "Vector2i(1, 2)"],
		[Vector3(1.0, 2.0, 3.0), &"Vector3", "Vector3(1.0, 2.0, 3.0)"],
		[Vector3i(1, 2, 3), &"Vector3i", "Vector3i(1, 2, 3)"],
		[Vector4(1.0, 2.0, 3.0, 4.0), &"Vector4", "Vector4(1.0, 2.0, 3.0, 4.0)"],
		[Vector4i(1, 2, 3, 4), &"Vector4i", "Vector4i(1, 2, 3, 4)"],
	]

	for case: Array in cases:
		var value: Variant = case[0]
		var type_name: StringName = case[1]
		var expected: String = case[2]
		var written: String = ComposerValueCodec.encode_variant(value, type_name)

		assert_eq(written, expected, "%s writes as %s" % [type_name, expected])
		var read: Dictionary = _read(type_name, written)
		assert_true(_ok(read), "%s reads back" % type_name)
		var same: bool = _value(read) == value
		assert_true(same, "%s reads back as itself" % type_name)


## A float keeps its point, so a `0` written for a float parameter does not read
## back as an int and quietly change what the call means.
func test_a_whole_float_still_writes_its_point() -> void:
	assert_eq(ComposerValueCodec.encode_variant(0.0, &"float"), "0.0")
	assert_eq(ComposerValueCodec.encode_variant(2.0, &"float"), "2.0")


func test_a_colour_writes_all_four_channels() -> void:
	var written: String = ComposerValueCodec.encode_variant(
		Color(0.5, 0.25, 0.0, 1.0), &"Color"
	)

	assert_eq(written, "Color(0.5, 0.25, 0.0, 1.0)")
	var read: Dictionary = ComposerValueCodec.parse_color(written)
	assert_true(_ok(read), "and reads back")
	var same: bool = _value(read) == Color(0.5, 0.25, 0.0, 1.0)
	assert_true(same, "as the same colour")


func test_a_quote_inside_a_string_is_escaped_and_recovered() -> void:
	var written: String = ComposerValueCodec.encode_variant("say \"hi\"", &"String")

	assert_eq(written, "\"say \\\"hi\\\"\"", "escaped on the way out")
	var read: Dictionary = ComposerValueCodec.parse_string(written)
	assert_true(_ok(read), "and read back")
	var same: bool = _value(read) == "say \"hi\""
	assert_true(same, "unescaped, as it was")
#endregion


#region Resources
## A saved Resource is named by its path, and preloaded so the parser and the
## exporter both see it.
func test_a_saved_resource_writes_as_a_preload_of_its_path() -> void:
	var saved: Resource = preload(
		"res://addons/GAS_Engine/icons/gas_engine_asc.svg"
	)

	assert_eq(
		ComposerValueCodec.encode_variant(saved, &"Resource"),
		"preload(\"%s\")" % saved.resource_path
	)


## One nobody saved has no path to name, so the codec writes nothing at all.
##
## Nothing, rather than something: inventing a path would put a line in the file
## that cannot load, and the caller's correct move is to leave what was there.
func test_an_unsaved_resource_refuses_to_be_written() -> void:
	assert_eq(ComposerValueCodec.encode_variant(Resource.new(), &"Resource"), "")
#endregion


#region What is not a literal
## An expression is not parsed, guessed at, or evaluated.
func test_an_expression_is_not_read_as_a_literal() -> void:
	for text: String in [
		"pick.target_data", "transform(pick)", "1 + 1", "burning", "Vector2(x, 0.0)"
	]:
		var field: ComposerNode.Field = ComposerNode.Field.new()
		field.type_name = &"Vector2" if text.begins_with("Vector2") else &"int"
		field.display = text

		assert_false(
			ComposerValueCodec.is_literal(field), "%s is an expression" % text
		)


## The marks matter: `&"x"` is a StringName and `"x"` is not.
func test_the_quoting_mark_decides_which_type_was_written() -> void:
	assert_false(_ok(ComposerValueCodec.parse_string("&\"x\"")), "a name is not a String")
	assert_false(_ok(ComposerValueCodec.parse_string("^\"x\"")), "nor is a path")
	assert_false(
		_ok(ComposerValueCodec.parse_string_name("\"x\"")), "and a String is not a name"
	)
#endregion


#region Defaults
## Every declared type has something Composer can write for it.
func test_every_type_in_the_default_map_writes_something() -> void:
	for type_name: StringName in ComposerTypes.DEFAULTS:
		assert_false(
			ComposerTypes.default_expression(type_name).is_empty(),
			"%s has a default" % type_name
		)


## A type nobody mapped is `null`, which compiles, rather than empty, which does
## not.
func test_an_unmapped_type_defaults_to_null() -> void:
	assert_eq(ComposerTypes.default_expression(&"SomeGameClass"), "null")
	assert_eq(ComposerTypes.default_expression(&""), "null")


## The engine's own default wins over the type's zero.
func test_a_declared_default_is_preferred_over_the_type_zero() -> void:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.type_name = &"float"
	field.variant_type = TYPE_FLOAT

	assert_eq(ComposerValueCodec.default_for(field, [2.5], 0), "2.5", "what it declares")
	assert_eq(ComposerValueCodec.default_for(field, [], -1), "0.0", "and the zero when not")


## A declared default the codec cannot write falls back rather than vanishing.
##
## An argument left out of a created call is a call that does not compile, so
## "cannot write this value" must not become "write no value".
func test_an_unwritable_declared_default_falls_back_to_the_type_zero() -> void:
	var field: ComposerNode.Field = ComposerNode.Field.new()
	field.type_name = &"int"
	field.variant_type = TYPE_INT

	assert_eq(ComposerValueCodec.default_for(field, [Resource.new()], 0), "0")


## Nothing Composer creates is born with an argument missing.
##
## The gate of this task, asked of the whole catalog rather than of one example:
## a call written with a required argument left out does not compile, and the
## person who clicked a node in the palette did not ask for a broken line.
func test_no_call_the_factory_writes_leaves_an_argument_empty() -> void:
	var checked: int = 0
	for group: StringName in ComposerCatalog.groups():
		for key: StringName in ComposerCatalog.entries(group):
			var entry: ComposerCatalog.Entry = ComposerCatalog.find(key)
			if entry == null:
				continue
			var written: PackedStringArray = ComposerStatementFactory.arguments(entry)

			assert_eq(
				written.size(), entry.parameters.size(),
				"%s writes every argument it declares" % key
			)
			for argument: String in written:
				assert_false(
					argument.strip_edges().is_empty(),
					"%s writes nothing empty" % key
				)
			checked += 1

	assert_gt(checked, 0, "the catalog offers something to check")


## And the one the plan names: a delay is created with its seconds.
func test_wait_delay_is_created_holding_a_number() -> void:
	var entry: ComposerCatalog.Entry = ComposerCatalog.find(
		ComposerCatalog.key_for(
			ComposerCatalog.script_for(ComposerCatalog.ABILITY_CLASS), &"wait_delay"
		)
	)

	assert_not_null(entry, "the catalog offers a delay")
	assert_true(
		ComposerStatementFactory.call_statement(entry, "res://probe.gd").contains("0.0"),
		"created holding a number rather than an empty pair of brackets"
	)
#endregion


func _read(type_name: StringName, text: String) -> Dictionary:
	match String(type_name):
		"bool":
			return ComposerValueCodec.parse_bool(text)
		"int":
			return ComposerValueCodec.parse_int(text)
		"float":
			return ComposerValueCodec.parse_float(text)
		"String":
			return ComposerValueCodec.parse_string(text)
		"StringName":
			return ComposerValueCodec.parse_string_name(text)
		"NodePath":
			return ComposerValueCodec.parse_node_path(text)
		"Vector2":
			return ComposerValueCodec.parse_vector2(text)
		"Vector2i":
			return ComposerValueCodec.parse_vector2(text, true)
		"Vector3":
			return ComposerValueCodec.parse_vector3(text)
		"Vector3i":
			return ComposerValueCodec.parse_vector3(text, true)
		"Vector4":
			return ComposerValueCodec.parse_vector4(text)
		"Vector4i":
			return ComposerValueCodec.parse_vector4(text, true)
	return {OK: false, VALUE: null}


#region Text that only looks like text
## An expression that begins and ends with a quote is not one string.
##
## `"fire" if hot else "ice"` does both. Read as a literal, the value editor
## would offer it in a text box and write it back as the single string
## `"fire\" if hot else \"ice"` - working code turned into a broken constant by
## somebody clicking on the argument that holds it.
const NOT_ONE_STRING: Array = [
	["\"fire\" if hot else \"ice\"", "a conditional between two strings"],
	["\"a\" + \"b\"", "two strings added"],
	["\"%s\" % named", "a format expression"],
]


func test_an_expression_between_two_quotes_is_not_a_string_literal() -> void:
	for row: Array in NOT_ONE_STRING:
		var written: String = row[0]
		var described: String = row[1]

		var read: Dictionary = ComposerValueCodec.parse_string(written)
		var understood: bool = read[ComposerValueCodec.OK]
		assert_false(understood, described)


## A real string still reads, including one carrying escaped quotes.
func test_a_real_string_still_reads_escapes_and_all() -> void:
	var plain: Dictionary = ComposerValueCodec.parse_string("\"burn\"")
	var plain_ok: bool = plain[ComposerValueCodec.OK]
	var plain_value: String = plain[ComposerValueCodec.VALUE] if plain_ok else ""
	assert_true(plain_ok, "an ordinary string")
	assert_eq(plain_value, "burn")

	var quoted: String = ComposerValueCodec.encode_variant("he said \"go\"", &"String")
	var read: Dictionary = ComposerValueCodec.parse_string(quoted)
	var read_ok: bool = read[ComposerValueCodec.OK]
	var read_value: String = read[ComposerValueCodec.VALUE] if read_ok else ""
	assert_true(read_ok, "one this codec wrote: %s" % quoted)
	assert_eq(read_value, "he said \"go\"", "round trips")
#endregion
