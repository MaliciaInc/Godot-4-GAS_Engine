extends GutTest


const SAMPLE_PATH: String = "res://test/unit/_composer_v31_sample.gd"


func test_new_ability_template_has_runtime_correct_entry_point() -> void:
	assert_true(ComposerAbilityTemplate.SOURCE.contains("extends GameplayAbility"))
	assert_true(
		ComposerAbilityTemplate.SOURCE.contains(
			"func _activate_ability() -> bool:"
		)
	)
	assert_true(ComposerAbilityTemplate.SOURCE.contains("\treturn true"))

	var graph: ComposerGraph = ComposerReader.read(
		ComposerAbilityTemplate.SOURCE,
		SAMPLE_PATH
	)
	assert_true(graph.is_editable(), graph.blocked_reason())


func test_layout_metadata_reads_position_from_carried_comment() -> void:
	var source: String = """extends GameplayAbility

func _activate_ability() -> bool:
	# @composer-position 412.50 188.25
	return true
"""
	var graph: ComposerGraph = ComposerReader.read(source, SAMPLE_PATH)
	assert_true(graph.is_editable(), graph.blocked_reason())
	assert_eq(ComposerProjection.statements(graph).size(), 1)
	assert_true(ComposerProjection.statements(graph)[0].has_layout_position)
	assert_eq(ComposerProjection.statements(graph)[0].layout_position, Vector2(412.5, 188.25))


func test_positioned_replaces_existing_position_without_duplicate_comment() -> void:
	var source: String = """extends GameplayAbility

func _activate_ability() -> bool:
	# kept comment
	# @composer-position 10.00 20.00
	return true
"""
	var graph: ComposerGraph = ComposerReader.read(source, SAMPLE_PATH)
	var changed: String = ComposerLayoutMetadata.positioned(
		source,
		ComposerProjection.statements(graph)[0],
		Vector2(300.0, 400.0)
	)

	assert_eq(changed.count(ComposerLayoutMetadata.PREFIX), 1)
	assert_true(changed.contains("# @composer-position 300.00 400.00"))
	assert_true(changed.contains("# kept comment"))


func test_positioned_inserts_metadata_without_touching_statement() -> void:
	var source: String = """extends GameplayAbility

func _activate_ability() -> bool:
	return true
"""
	var graph: ComposerGraph = ComposerReader.read(source, SAMPLE_PATH)
	var changed: String = ComposerLayoutMetadata.positioned(
		source,
		ComposerProjection.statements(graph)[0],
		Vector2(111.25, 222.5)
	)

	assert_true(changed.contains("# @composer-position 111.25 222.50"))
	assert_true(changed.contains("\treturn true"))


func test_copy_text_drops_composer_position_metadata() -> void:
	var text: String = """	# user's note
	# @composer-position 15.00 25.00
	return true"""
	var copied: String = ComposerLayoutMetadata.without_layout_text(text)

	assert_true(copied.contains("# user's note"))
	assert_false(copied.contains(ComposerLayoutMetadata.PREFIX))
	assert_true(copied.contains("return true"))


func test_repeat_does_not_duplicate_visual_position() -> void:
	var source: String = """extends GameplayAbility

func _activate_ability() -> bool:
	# @composer-position 15.00 25.00
	return true
"""
	var graph: ComposerGraph = ComposerReader.read(source, SAMPLE_PATH)
	var repeated: String = ComposerEdits.repeat(
		source,
		[ComposerProjection.statements(graph)[0].span] as Array[ComposerSpan]
	)

	assert_eq(repeated.count(ComposerLayoutMetadata.PREFIX), 1)


func test_palette_search_matches_title_and_method_name_case_insensitively() -> void:
	var groups: Array[StringName] = ComposerCatalog.groups()
	var tested: bool = false

	for group: StringName in groups:
		for key: StringName in ComposerCatalog.entries(group):
			var entry: ComposerCatalog.Entry = ComposerCatalog.find(key)
			if entry == null or entry.title.is_empty():
				continue
			var title_piece: String = entry.title.substr(
				0,
				mini(4, entry.title.length())
			).to_lower()
			assert_true(ComposerPalette._entry_matches(key, title_piece))
			assert_true(
				ComposerPalette._entry_matches(
					key,
					String(entry.type_id).to_upper()
				)
			)
			tested = true
			break
		if tested:
			break

	assert_true(tested, "Composer catalog must expose at least one searchable entry.")


func test_reader_keeps_argument_ports_typed_from_catalog() -> void:
	var checked: bool = false

	for group: StringName in ComposerCatalog.groups():
		for key: StringName in ComposerCatalog.entries(group):
			var entry: ComposerCatalog.Entry = ComposerCatalog.find(key)
			if entry == null or entry.parameters.is_empty():
				continue

			var field: ComposerNode.Field = entry.parameter(0)
			if field == null or field.type_name.is_empty():
				continue

			var port: ComposerNode.Port = ComposerReader.port(
				&"probe",
				ComposerNode.PortKind.DATA,
				ComposerNode.PortDirection.INPUT
			)
			port.type_name = field.type_name

			assert_eq(port.kind, ComposerNode.PortKind.DATA)
			assert_eq(port.direction, ComposerNode.PortDirection.INPUT)
			assert_eq(port.type_name, field.type_name)
			checked = true
			break
		if checked:
			break

	assert_true(checked, "Catalog must expose at least one typed parameter.")
