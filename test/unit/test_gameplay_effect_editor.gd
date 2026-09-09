## Authoring an effect: what the editor may do to one, and the promise that
## opening and saving it changes nothing on its own.
##
## Everything here drives the document rather than the screen, which is the
## point of the split: what an edit means is a question with a right answer, and
## a question with a right answer should be answerable without standing up a
## window.
##
## The effect files these tests read are written by the tests, into `user://`,
## and deleted afterwards. A `.tres` checked into the repository as a fixture
## would be a case expressible in GDScript stored as data instead.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const WRITTEN: String = "user://gas_engine_effect_editor_test.tres"
const HEALTH: StringName = &"health"

var document: GameplayEffectDocument = null


func before_each() -> void:
	document = GameplayEffectDocument.new()


func after_each() -> void:
	document = null
	if FileAccess.file_exists(WRITTEN):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WRITTEN))


#region Getting there
## Put an effect on disk for the editor to open, the way a project would have.
func _written(effect: GameplayEffect) -> String:
	assert_eq(ResourceSaver.save(effect, WRITTEN), OK, "the fixture was written")
	return WRITTEN


## Every property the engine will serialise, as a dictionary.
##
## What "structurally equivalent" means for a Resource: Godot decides how to
## write a file and may normalise it, so comparing bytes would be comparing
## Godot's formatting rather than the effect. This compares what the effect is.
func _serialised(effect: GameplayEffect) -> Dictionary:
	return _described(effect, 0)


## One Resource, described by what it stores rather than by what it is.
##
## Recursive, because an effect's interesting content is nested Resources -
## the modifiers, their magnitudes, the components - and a reloaded one is a
## different object every time. Comparing the objects would compare identity,
## which is guaranteed to differ and says nothing about the effect.
func _described(value: Variant, depth: int) -> Dictionary:
	var said: Dictionary = {}
	if not value is Resource:
		return said
	var resource: Resource = value
	if resource == null or depth > 6:
		return said
	for property: Dictionary in resource.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var name: String = property["name"]
		said[name] = _value_of(resource.get(name), depth)
	return said


## What one stored value is, with every object in it described rather than
## named.
func _value_of(held: Variant, depth: int) -> Variant:
	if held is Array:
		var listed: Array = []
		var entries: Array = held
		for entry: Variant in entries:
			listed.append(_value_of(entry, depth + 1))
		return listed
	if held is Resource:
		return _described(held, depth + 1)
	if held is Object:
		# A plain Object has no storage to walk and its address means nothing
		# across a reload; that it is there is the whole of what can be said.
		return "an object"
	return str(held)
#endregion


#region Opening and saving
## Opening reads what is there; opening nothing changes nothing.
##
## The second half matters more: an editor that kept showing the last thing it
## opened while claiming to show a new one is worse than one showing nothing.
func test_opening_reads_the_effect_and_a_bad_path_leaves_it_alone() -> void:
	var path: String = _written(Factory.instant([Factory.add(HEALTH, -10.0)]))

	assert_true(document.open(path), "it opened")
	assert_eq(document.effect.modifiers.size(), 1, "and read what was in it")

	var still: GameplayEffect = document.effect
	assert_false(document.open("user://nothing_is_here.tres"), "nothing to open")
	assert_eq(document.effect, still, "so nothing was opened")


## Load, open in the editor, save without editing, reload: the same effect.
##
## The regression the whole "no shadow model" decision exists for. An editor
## with its own description of an effect loses whatever its description has no
## word for, and the loss shows up as an effect that quietly stopped doing
## something between one save and the next.
func test_opening_and_saving_without_editing_changes_nothing() -> void:
	var authored: GameplayEffect = Factory.stacked(
		Factory.granting(
			Factory.duration([Factory.add(HEALTH, -5.0)], 12.0),
			[&"Status.Bleeding"] as Array[StringName]
		),
		GameplayEffect.StackingType.AGGREGATE_BY_SOURCE,
		4
	)
	Factory.with_application_cues(authored, [&"Cue.Bleed"] as Array[StringName])
	var before: Dictionary = _serialised(authored)
	var path: String = _written(authored)

	assert_true(document.open(path), "it opened")
	assert_true(document.save(), "and saved")

	var reloaded: GameplayEffect = ResourceLoader.load(
		path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as GameplayEffect
	assert_not_null(reloaded, "it came back")
	assert_eq(_serialised(reloaded), before, "and it is the same effect")


## An effect nobody chose a home for cannot be saved, and says so.
##
## Choosing one is a decision the document is not entitled to make: a file
## written somewhere the author did not ask for is a file they will find later
## and not recognise.
func test_an_effect_with_nowhere_to_live_refuses_to_save() -> void:
	assert_true(document.adopt(Factory.instant([] as Array[GameplayEffectModifier])))

	assert_false(document.save(), "it refused rather than choosing a path")
#endregion


#region One action builds the whole row
## Adding a modifier builds the chain a person had to build four Resources for.
##
## The modifier, the magnitude, the scalable float behind it, and a typed
## attribute reference to fill in. This is the friction F6.0.9 measured as four,
## and the reason it is one action rather than one object.
func test_adding_a_modifier_builds_the_whole_chain() -> void:
	document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))

	var modifier: GameplayEffectModifier = document.add_modifier()

	assert_not_null(modifier, "a row arrived")
	assert_not_null(modifier.attribute, "with somewhere to name an attribute")
	assert_not_null(document.magnitude_at(0), "and a magnitude")
	assert_not_null(document.magnitude_at(0).value, "and the number behind it")


## The three things a row says, set through the document and read off the
## effect - because the effect is the model, and there is no other copy.
func test_a_row_says_what_it_changes_how_and_where() -> void:
	document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	document.add_modifier()

	var reference: GameplayAttributeRef = GameplayAttributeRef.new()
	reference.attribute_name = HEALTH
	assert_true(document.set_modifier_attribute(0, reference), "which attribute")
	assert_true(
		document.set_modifier_operation(0, GameplayEffectModifier.Operation.MULTIPLY),
		"how"
	)
	assert_true(document.set_modifier_amount(0, 1.5), "how much")
	assert_true(document.set_modifier_channel(0, 3), "and where in the composition")

	var written: GameplayEffectModifier = document.effect.modifiers[0]
	assert_eq(written.attribute.attribute_name, HEALTH, "the typed reference")
	assert_eq(written.attribute_name, HEALTH, "and the legacy name, in step with it")
	assert_eq(written.operation, GameplayEffectModifier.Operation.MULTIPLY, "the operation")
	assert_almost_eq(document.magnitude_at(0).value.value, 1.5, TOLERANCE, "the amount")
	assert_eq(written.evaluation_channel, 3, "the channel")


## A channel outside the ten that exist is clamped rather than stored.
##
## An effect carrying channel forty is one the aggregate would never read, and
## the author would be waiting for a modifier that never applies.
func test_a_channel_that_does_not_exist_is_brought_back_into_range() -> void:
	document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	document.add_modifier()

	document.set_modifier_channel(0, 40)

	assert_eq(
		document.effect.modifiers[0].evaluation_channel,
		AttributeAggregateMath.CHANNELS - 1,
		"the last channel there is"
	)
#endregion


#region Components
## A component the runtime reads only the first of cannot be added twice.
##
## The editor asks the component rather than keeping its own list, so the two
## cannot disagree about which kind it is.
##
##     [what it is called, a component, whether a second is allowed]
func _duplicate_cases() -> Array:
	return [
		["one the runtime reads all of", true],
		["one it reads the first of", false],
	]


func test_a_component_the_runtime_reads_once_cannot_be_added_twice(
	case: Array = use_parameters(_duplicate_cases())
) -> void:
	var described: String = case[0]
	var many: bool = case[1]
	document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))

	var first: GameplayEffectComponent = (
		GameplayEffectAssetTagsComponent.new()
		if many
		else GameplayEffectImmunityComponent.new()
	)
	var second: GameplayEffectComponent = (
		GameplayEffectAssetTagsComponent.new()
		if many
		else GameplayEffectImmunityComponent.new()
	)

	assert_true(document.add_component(first), "%s: the first one" % described)
	assert_eq(document.add_component(second), many, "%s: and the second" % described)
	assert_eq(
		document.effect.components.size(), 2 if many else 1, "%s: what is on it" % described
	)


func test_a_component_can_be_taken_off_again() -> void:
	document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	document.add_component(GameplayEffectAssetTagsComponent.new())

	assert_true(document.remove_component(0), "it came off")
	assert_eq(document.effect.components.size(), 0, "and nothing is left")
	assert_false(document.remove_component(0), "and taking off nothing is refused")
#endregion


#region Stacking, cues and what is wrong with it
func test_stacking_and_cues_are_authored_through_the_document() -> void:
	document.adopt(Factory.infinite([] as Array[GameplayEffectModifier]))

	document.set_stacking(GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 3)
	document.add_cue(&"Cue.Impact", GameplayCueBinding.Type.EXECUTED_ON_APPLICATION)

	assert_eq(
		document.effect.stacking_type,
		GameplayEffect.StackingType.AGGREGATE_BY_TARGET,
		"how it stacks"
	)
	assert_eq(document.effect.stack_limit_count, 3, "and how many")
	assert_eq(document.effect.cues.size(), 1, "and what it plays")
	assert_eq(document.effect.cues[0].cue_tag, &"Cue.Impact", "under which tag")


## What the editor says is wrong is what the engine says is wrong.
##
## The same validator rather than a second opinion written for the editor: an
## editor that thought an effect was fine while the engine refused it would be
## worse than no editor at all.
func test_the_editor_reports_what_the_engine_would_refuse() -> void:
	var stacking: GameplayEffect = Factory.infinite(
		[] as Array[GameplayEffectModifier]
	)
	document.adopt(stacking)
	# The stack-count question is a warning under Unreal's contracts and
	# nothing at all under the native ones, so the editor is told which.
	document.profile = GameplayCompatibilityProfile.new()
	document.profile.mode = GameplayCompatibilityProfile.Mode.UE_5_7
	document.set_stacking(GameplayEffect.StackingType.AGGREGATE_BY_TARGET, 0)

	var said: Array[GameplayAssetValidationResult] = document.validation()

	var codes: Array[int] = []
	for finding: GameplayAssetValidationResult in said:
		codes.append(int(finding.code))
	assert_true(
		codes.has(int(GameplayAssetValidationResult.Code.STACKING_WITHOUT_STACK_COUNT_ANSWER)),
		"a stacking effect that never answered the stack question"
	)


## Every edit announces itself once, so a screen can redraw without every edit
## method knowing a screen exists.
func test_every_edit_announces_itself() -> void:
	document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	var heard: Array[int] = [0]
	document.changed.connect(func() -> void: heard[0] += 1)

	document.add_modifier()
	document.set_duration(3.0)
	document.add_cue(&"Cue.X", GameplayCueBinding.Type.EXECUTED_ON_APPLICATION)

	assert_eq(heard[0], 3, "three edits, three announcements")
#endregion


#region The screen is a projection
## The screen shows what the document holds, and shows it again after an edit.
##
## The whole reason the screen keeps no state of its own: a row list built once
## and patched afterwards is a list that goes stale the first time an edit
## nobody thought about changes what is in it.
func test_the_screen_shows_what_the_document_holds() -> void:
	var screen: GameplayEffectEditor = GameplayEffectEditor.new()
	add_child_autofree(screen)
	screen.document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	screen.refresh()

	assert_eq(_rows_on(screen), 0, "nothing to show yet")

	screen.document.add_modifier()
	screen.document.add_modifier()

	assert_eq(_rows_on(screen), 2, "two rows, without anybody asking it to redraw")


## A row shows the modifier's own values rather than what somebody typed.
##
## Which is the difference that matters when an edit is clamped: a channel of
## forty becomes nine, and a row showing forty would be a row that lies.
func test_a_row_shows_what_was_stored_rather_than_what_was_typed() -> void:
	var screen: GameplayEffectEditor = GameplayEffectEditor.new()
	add_child_autofree(screen)
	screen.document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	screen.document.add_modifier()
	screen.document.set_modifier_channel(0, 40)

	var row: EffectModifierRow = _first_row(screen)
	assert_not_null(row, "there is a row")
	row.show_what_is_there()
	assert_eq(
		int(row._channel.value),
		AttributeAggregateMath.CHANNELS - 1,
		"the channel it was given, not the one that was typed"
	)


## The menu offers every component the addon has, and disables the one this
## effect already has the only one of.
##
## Disabled rather than hidden: hidden, an author looks for it and concludes
## the addon has no such component.
func test_the_menu_offers_everything_and_disables_what_is_already_there() -> void:
	var screen: GameplayEffectEditor = GameplayEffectEditor.new()
	add_child_autofree(screen)
	screen.document.adopt(Factory.instant([] as Array[GameplayEffectModifier]))
	screen.document.add_component(GameplayEffectImmunityComponent.new())

	var menu: EffectComponentMenu = _menu_on(screen)
	menu.offer_for(screen.document)

	assert_eq(
		menu.item_count,
		EffectComponentMenu.available_components().size(),
		"every component the addon ships"
	)
	assert_eq(menu.item_count, 12, "which is twelve of them")
	var disabled: int = 0
	for index: int in menu.item_count:
		if menu.is_item_disabled(index):
			disabled += 1
	assert_eq(disabled, 1, "and exactly the one it already has is closed off")


## Every row and the menu, found the way the screen arranged them.
func _rows_on(screen: GameplayEffectEditor) -> int:
	var seen: int = 0
	for node: Node in _descendants(screen):
		if node is EffectModifierRow:
			seen += 1
	return seen


func _first_row(screen: GameplayEffectEditor) -> EffectModifierRow:
	for node: Node in _descendants(screen):
		var row: EffectModifierRow = node as EffectModifierRow
		if row != null:
			return row
	return null


func _menu_on(screen: GameplayEffectEditor) -> EffectComponentMenu:
	for node: Node in _descendants(screen):
		var menu: EffectComponentMenu = node as EffectComponentMenu
		if menu != null:
			return menu
	return null


func _descendants(of: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in of.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
#endregion
