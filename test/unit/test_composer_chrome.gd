## The panels around the canvas: palette, inspector, output, and the bar.
##
## What is worth pinning here is not that a label exists but that two surfaces
## describing the same fact agree, and that a panel says plainly when it has
## nothing to show. Both are failures a person meets late and trusts least.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Sample = preload("res://test/fixtures/composer_sample_graph.gd")

const PANEL_WIDTH: float = 290.0
const PANEL_HEIGHT: float = 400.0


func _mounted(control: Control, span: Vector2) -> Control:
	control.size = span
	add_child_autofree(control)
	return control


## Press the button carrying this exact text, wherever it is.
func _press_titled(parent: Node, title: String) -> bool:
	for child: Node in parent.get_children():
		if child is Button and (child as Button).text == title:
			(child as Button).pressed.emit()
			return true
		if _press_titled(child, title):
			return true
	return false


func _labels(parent: Node, found: Array[String]) -> Array[String]:
	for child: Node in parent.get_children():
		if child is Label:
			found.append((child as Label).text)
		elif child is Button:
			found.append((child as Button).text)
		_labels(child, found)
	return found


#region Palette
## The palette shows the catalog, it does not keep its own copy of it.
##
## A view owning the vocabulary is a view that decides what the Composer can
## express, and the next thing to need that list would grow a second one.
func test_the_palette_lists_every_group_the_catalog_declares() -> void:
	var palette: ComposerPalette = _mounted(
		ComposerPalette.new(), Vector2(250.0, PANEL_HEIGHT)
	) as ComposerPalette

	var shown: Array[String] = _labels(palette, [] as Array[String])
	for group: StringName in ComposerCatalog.groups():
		assert_true(shown.has(String(group)), "%s is offered" % group)


## One group open at a time: a palette with everything expanded is a list
## nobody can scan.
func test_opening_a_group_closes_the_one_that_was_open() -> void:
	var palette: ComposerPalette = _mounted(
		ComposerPalette.new(), Vector2(250.0, PANEL_HEIGHT)
	) as ComposerPalette
	var first: StringName = palette.open_group_name()

	palette.open_group(ComposerCatalog.EFFECTS)

	assert_eq(palette.open_group_name(), ComposerCatalog.EFFECTS, "the new one is open")
	assert_ne(palette.open_group_name(), first, "and the old one is not")
#endregion


#region Inspector
## An empty panel and a panel showing nothing look identical, and one of them is
## a bug. Saying it out loud removes the question.
func test_the_inspector_says_when_nothing_is_selected() -> void:
	var inspector: ComposerInspector = _mounted(
		ComposerInspector.new(), Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	) as ComposerInspector
	inspector.show_node(null)

	assert_true(
		_labels(inspector, [] as Array[String]).has(ComposerInspector.NOTHING_SELECTED),
		"an empty inspector is not left to be guessed at"
	)


## The card and the inspector read the same field, so they cannot describe it
## differently. This is that agreement, checked rather than assumed.
func test_a_missing_value_reads_the_same_here_as_on_the_card() -> void:
	var inspector: ComposerInspector = _mounted(
		ComposerInspector.new(), Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	) as ComposerInspector
	inspector.show_node(Sample.build().find_node(Sample.CUE))

	assert_true(
		_labels(inspector, [] as Array[String]).has(ComposerCard.MISSING_LABEL),
		"the same words the card uses"
	)


## Collapsing has to hand the width back. A panel that hides its contents while
## still reserving its column has not collapsed, it has gone blank.
func test_collapsing_the_inspector_returns_its_width() -> void:
	var inspector: ComposerInspector = _mounted(
		ComposerInspector.new(), Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	) as ComposerInspector
	var open: float = inspector.occupied_width()

	inspector.toggle()

	assert_true(inspector.is_collapsed(), "it folded")
	assert_lt(inspector.occupied_width(), open, "and the canvas gets the room")
#endregion


#region Output
func test_the_output_counts_in_words_that_match_the_number() -> void:
	var output: ComposerOutput = _mounted(
		ComposerOutput.new(), Vector2(700.0, 132.0)
	) as ComposerOutput
	output.show_graph(Sample.build())

	var shown: Array[String] = _labels(output, [] as Array[String])
	assert_true(shown.has("4 nodes · 1 note"), "not '1 notes': %s" % [shown])


## A file this tool cannot draw is not a mistake in the file, and the message
## has to say so - otherwise a person goes hunting for an error they did not
## make.
func test_an_unreadable_file_is_reported_as_read_only_rather_than_broken() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	graph.source_path = "res://abilities/chain.gd"
	var found: ComposerGraph.Diagnostic = ComposerGraph.Diagnostic.new()
	found.severity = ComposerGraph.Severity.NOT_REPRESENTABLE
	found.message = "uses for - line 42"
	found.span = ComposerSpan.new(42, 42)
	graph.diagnostics = [found] as Array[ComposerGraph.Diagnostic]

	var output: ComposerOutput = _mounted(
		ComposerOutput.new(), Vector2(700.0, 132.0)
	) as ComposerOutput
	output.show_graph(graph)

	var shown: Array[String] = _labels(output, [] as Array[String])
	assert_true(
		shown.has(ComposerOutput.READ_ONLY + found.message),
		"named as read-only, not as an error: %s" % [shown]
	)
	assert_true(shown.has("chain.gd:42"), "and pointed at its line")


func test_a_clean_graph_says_so_instead_of_showing_an_empty_list() -> void:
	var graph: ComposerGraph = ComposerGraph.new()
	var output: ComposerOutput = _mounted(
		ComposerOutput.new(), Vector2(700.0, 132.0)
	) as ComposerOutput
	output.show_graph(graph)

	assert_true(
		_labels(output, [] as Array[String]).has(ComposerOutput.NOTHING),
		"silence and success look the same otherwise"
	)

## A refusal is not silence.
##
## `show_graph(null)` and a refusal both leave the canvas empty, and for a while
## they were reported identically - which is how choosing Ability Composer with
## the wrong file open came to look like a menu item that did nothing. The
## reason has to be on the panel, and so does what to do about it.
func test_a_refusal_says_why_and_what_to_do_rather_than_reading_as_empty() -> void:
	var output: ComposerOutput = _mounted(
		ComposerOutput.new(), Vector2(700.0, 132.0)
	) as ComposerOutput
	output.show_refusal("gas_engine_plugin.gd does not extend GameplayAbility")

	var shown: Array[String] = _labels(output, [] as Array[String])
	assert_true(
		shown.has("gas_engine_plugin.gd does not extend GameplayAbility"),
		"the reason is on the panel: %s" % [shown]
	)
	assert_true(shown.has(ComposerOutput.HOW_TO_OPEN), "and so is the way out")
	assert_false(shown.has(ComposerOutput.NOTHING), "not reported as nothing to report")
#endregion


## Every severity has a colour and a mark.
##
## The two tables are indexed by the enum, which is fast and unforgiving: a
## severity added without an entry is an out-of-range read, and this is what
## turns that into a failing test rather than a crash in front of a user.
func test_every_severity_has_a_colour_and_a_mark() -> void:
	var count: int = ComposerGraph.Severity.size()
	assert_eq(ComposerTheme.SEVERITY_COLORS.size(), count, "a colour for each")
	assert_eq(ComposerTheme.SEVERITY_MARKS.size(), count, "and a mark for each")

	for value: int in count:
		var severity: ComposerGraph.Severity = value as ComposerGraph.Severity
		assert_ne(ComposerTheme.severity_mark(severity), "", "%d has a glyph" % value)
#endregion


#region The screen
## One graph, handed to everything that draws part of it.
##
## Two calls would let the canvas and the output end up describing different
## files, which is the kind of wrong a person notices last.
func test_one_graph_reaches_both_the_canvas_and_the_output() -> void:
	var screen: ComposerScreen = _mounted(
		ComposerScreen.new(), Vector2(1280.0, 720.0)
	) as ComposerScreen
	await get_tree().process_frame
	await screen.show_graph(Sample.build())

	var shown: Array[String] = _labels(screen, [] as Array[String])
	assert_true(shown.has("Sample"), "the bar names the open ability")
	assert_true(shown.has("4 nodes · 1 note"), "and the output counted the same one")


## `Code` asks; it does not open. The plugin owns the editor, and a view that
## reached for it would be a view that knows about Godot's docks.
func test_asking_for_the_code_names_the_file_rather_than_opening_it() -> void:
	var screen: ComposerScreen = _mounted(
		ComposerScreen.new(), Vector2(1280.0, 720.0)
	) as ComposerScreen
	await get_tree().process_frame
	await screen.show_graph(Sample.build())

	var asked: Array[String] = []
	screen.code_requested.connect(func _asked(path: String) -> void: asked.append(path))
	screen._on_code_pressed()

	assert_eq(asked.size(), 1, "it asked once")
	assert_eq(asked[0], "res://abilities/sample.gd", "naming the file it is a view of")
#endregion


## A node offered after the panel was built shows up the next time a file opens.
##
## The palette is drawn once and lives as long as the editor. A game that
## registers later would otherwise see nothing happen and conclude the door does
## not work.
func test_a_node_registered_later_reaches_the_palette() -> void:
	var palette: ComposerPalette = autofree(ComposerPalette.new())
	palette.size = Vector2(240.0, 600.0)
	add_child_autofree(palette)
	await wait_frames(1)

	assert_eq(
		ComposerCatalog.register(
			"spend_stamina", &"Stamina", "res://test/fixtures/game_composer_nodes.gd", false
		),
		"",
		"a game offers a call"
	)
	palette.refresh()
	palette.open_group(&"Stamina")

	assert_eq(palette.open_group_name(), &"Stamina", "the new category can be opened")
	ComposerCatalog.forget(
		ComposerCatalog.key_for(
			"res://test/fixtures/game_composer_nodes.gd", &"spend_stamina"
		)
	)


## A row in the Output panel takes you to the node it is about.
##
## Read end to end through the screen rather than by calling the canvas: the
## signal, its connection and the reveal are three separate things, and a test
## that skips the middle one passes while the panel does nothing.
func test_clicking_an_output_row_reveals_that_node_on_the_canvas() -> void:
	var screen: ComposerScreen = autofree(ComposerScreen.new())
	screen.size = Vector2(1400.0, 800.0)
	add_child_autofree(screen)
	await wait_frames(1)

	var source: String = (
		"extends GameplayAbility\n\n\nfunc _activate_ability() -> void:\n"
		+ "\tcommit_ability()\n\tadd_tag()\n"
	)
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")
	await screen.show_graph(graph)

	assert_eq(graph.diagnostics.size(), 1, "the body has one thing wrong with it")
	screen._on_row_picked(graph.diagnostics[0].node_id, 0)

	assert_eq(
		screen.canvas().picked(), [graph.diagnostics[0].node_id] as Array[StringName],
		"the node the row was about"
	)


## The whole screen comes forward on a refusal, not just the panel.
##
## This is the half that was missing when the bug was reported: the reason was
## pushed to the console and the editor stayed on whatever screen it was on, so
## from where the person sat, choosing the menu item did nothing at all.
func test_a_refused_open_still_leaves_the_screen_showing_the_reason() -> void:
	var screen: ComposerScreen = _mounted(
		ComposerScreen.new(), Vector2(1280.0, 720.0)
	) as ComposerScreen
	await get_tree().process_frame
	await screen.show_refusal("there is nothing at res://nowhere.gd")

	var shown: Array[String] = _labels(screen, [] as Array[String])
	assert_true(shown.has(ComposerTopBar.NO_ABILITY), "the bar says nothing is open")
	assert_true(shown.has("there is nothing at res://nowhere.gd"), "and the panel says why")
	assert_null(screen.graph(), "with no graph behind it")


## What a palette row actually emits when it is pressed.
##
## The suite called the screen's handler directly, which proved the handler and
## never the wire between them. The wire was broken the whole time: the row
## emitted the catalog entry where the signal declares a StringName, so Godot
## refused the call at the connection and every palette click did nothing at
## all - silently, because the refusal happened before any code that could have
## reported it. A click reported from a real editor is what found it.
func test_pressing_a_palette_row_emits_a_key_the_catalog_can_find() -> void:
	var palette: ComposerPalette = _mounted(
		ComposerPalette.new(), Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	) as ComposerPalette
	await get_tree().process_frame

	var wanted: StringName = ComposerCatalog.all().keys()[0]
	var row: Button = palette._entry_row(wanted) as Button
	add_child_autofree(row)

	var heard: Array = []
	palette.node_picked.connect(func _picked(what: Variant) -> void: heard.append(what))
	row.pressed.emit()

	assert_eq(heard.size(), 1, "the press was heard")
	assert_eq(
		typeof(heard[0]), TYPE_STRING_NAME, "as the StringName the signal declares"
	)
	# Guarded, because the second claim only means anything once the first holds:
	# with the defect present this array held an Object, and looking a key up
	# from one would fail as a crash rather than as a message.
	if typeof(heard[0]) == TYPE_STRING_NAME:
		var emitted: StringName = heard[0]
		assert_not_null(ComposerCatalog.find(emitted), "and the catalog knows it")


## A refusal offers the way out, it does not only describe it.
##
## Telling somebody who arrived through a menu to go and open a file themselves
## is telling them the tool cannot do what they just asked for. The screen
## forwards the request rather than answering it, because choosing a file is
## the editor's business and this view knows nothing about docks.
func test_a_refusal_offers_to_open_one_and_the_screen_passes_that_on() -> void:
	var screen: ComposerScreen = _mounted(
		ComposerScreen.new(), Vector2(1280.0, 720.0)
	) as ComposerScreen
	await get_tree().process_frame
	await screen.show_refusal("the script editor has nothing open")

	var asked: Array[bool] = []
	screen.open_requested.connect(func _heard() -> void: asked.append(true))

	assert_true(_press_titled(screen, ComposerOutput.PICK_ONE), "the offer is on screen")
	assert_eq(asked.size(), 1, "and pressing it reaches whoever owns the editor")


## Mounted the way the editor mounts it: inside a container.
##
## `EditorInterface.get_editor_main_screen()` is a container, and a container
## sizes its children by their size flags and ignores their anchors completely.
## The screen was added with an anchors preset and no flags, so it was given its
## minimum height - a strip - and everything inside it went where a strip puts
## things: the palette overflowed its own bounds, the canvas was a sliver, and
## the Output panel was laid out at the top of the window instead of the bottom.
## From the editor it read as most of the interface being missing.
##
## Every other test here sets `size` by hand, which is why none of them could
## have caught it. This one refuses to, and asks the container instead.
func test_mounted_in_a_container_the_screen_is_given_the_whole_of_it() -> void:
	var mount: VBoxContainer = VBoxContainer.new()
	add_child_autofree(mount)
	mount.size = Vector2(1280.0, 900.0)

	var screen: ComposerScreen = ComposerScreen.new()
	mount.add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_almost_eq(screen.size.y, 900.0, 4.0, "the height it was offered")
	assert_almost_eq(screen.size.x, 1280.0, 4.0, "and the width")


#region What the spec fixes about how things read
## One missing argument, one severity.
##
## The card said it in amber and the Output row said it in red, over the same
## fact, and a comment in the card claimed the two agreed. A person reading the
## card would have concluded their ability still runs.
func test_a_missing_argument_is_the_same_severity_on_the_card_and_in_the_panel() -> void:
	var source: String = (
		"extends GameplayAbility


func _activate_ability() -> void:
	add_tag()
"
	)
	var graph: ComposerGraph = ComposerReader.read(source, "res://a.gd")

	assert_eq(graph.diagnostics.size(), 1, "the panel has something to say")
	assert_eq(
		graph.diagnostics[0].severity, ComposerGraph.Severity.ERROR, "and says it is an error"
	)
	assert_eq(
		graph.nodes[0].state, ComposerNode.State.ERROR, "and the card carries the same"
	)
	assert_eq(
		ComposerTheme.severity_color(
			ComposerNode.severity_of(graph.nodes[0].state)
		),
		ComposerTheme.severity_color(graph.diagnostics[0].severity),
		"so both are drawn in one colour"
	)


## A file this tool cannot draw is not drawn like a count of nodes.
##
## The reason went out in the same grey a node count is written in, which is how
## a reason ends up being read as a tally and skipped.
func test_a_read_only_reason_is_not_the_colour_of_a_count() -> void:
	var reason: Color = ComposerTheme.severity_color(
		ComposerGraph.Severity.NOT_REPRESENTABLE
	)

	assert_eq(reason, ComposerTheme.WARNING, "amber, because it wants reading")
	assert_ne(reason, ComposerTheme.TEXT_FAINT, "not the colour of the count")
	assert_ne(reason, ComposerTheme.TEXT_DIM, "nor of a label beside it")
	assert_ne(
		ComposerTheme.severity_mark(ComposerGraph.Severity.NOT_REPRESENTABLE),
		ComposerTheme.severity_mark(ComposerGraph.Severity.ERROR),
		"and it is not marked the way an error is"
	)
#endregion
