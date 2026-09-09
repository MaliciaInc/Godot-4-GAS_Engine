## F6.4's gate: one effect authored, aimed and watched, using every piece the
## package added and nothing else.
##
## Each piece has its own tests. This exists because pieces that pass separately
## can still be wrong together: an editor that writes a modifier the runtime
## reads differently, a picker that names an attribute nothing declares, a query
## the author nested one way and the runtime evaluates another, a tag renamed in
## one place and asked about in the other. The walk is one authoring session end
## to end - author, choose, nest, rename, apply, watch, aim.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

const TOLERANCE: float = 0.0001
const LINE_BREAK: String = "\n"

## What the author is putting on the effect, and what they are asking about.
const ATTACK: StringName = TestAttributeSet.ATTACK
const BUFF_AMOUNT: float = 10.0

## What the author calls the effect. Named, because a page that has to show what
## is on a character cannot show a blank - and an assertion against a blank name
## is an assertion that holds however wrong the page is.
const EFFECT_NAME: String = "AuthoredWalkBuff"

## The rename this walk performs: a project that shipped `Status.Stun` and now
## calls it `Status.Stunned`.
const OLD_TAG: StringName = &"Status.Stun"
const NEW_TAG: StringName = &"Status.Stunned"
const IMMUNE: StringName = &"Status.Immune"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null


func before_each() -> void:
	GameplayTagRedirects.forget()
	fixture = Fixture.create("Author")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)


func after_each() -> void:
	GameplayTagRedirects.forget()
	fixture = null
	asc = null


## Author an effect, choose an attribute, nest a query, redirect an old tag,
## apply, inspect four overlay pages, aim an area effect.
##
## One test rather than seven, because it is one session: each step works on
## what the last one produced, and splitting it would mean seven effects that
## never met.
func test_the_whole_authoring_contract_walks_from_an_empty_effect_to_an_aimed_area() -> void:
	var document: GameplayEffectDocument = _authored()
	var modifier: GameplayEffectModifier = document.effect.modifiers[0]

	_choose_the_attribute(document, modifier)
	var gate: GameplayTagQuery = _nest_the_query(document)
	_redirect_the_old_tag()

	var applied: ActiveGameplayEffect = _apply(document.effect)
	_inspect_four_pages(applied)
	_aim_an_area()

	assert_true(
		gate.matches_node(fixture.owner),
		"and the query the author nested still says what it said before any of it"
	)


#region The steps
## An effect authored in one action, in the editor's own document.
##
## The friction F6.0.9 measured: four Resources, each its own click. One call
## now, and what comes back is a complete row - which is what the walk then
## fills in rather than building itself.
func _authored() -> GameplayEffectDocument:
	var document: GameplayEffectDocument = GameplayEffectDocument.new()
	var authored: GameplayEffect = GameplayEffect.new()
	authored.resource_name = EFFECT_NAME
	assert_true(document.adopt(authored), "there is an effect to author")
	document.set_policy(GameplayEffect.DurationPolicy.INFINITE)

	var modifier: GameplayEffectModifier = document.add_modifier()
	assert_not_null(modifier, "one action produced the whole modifier row")
	assert_not_null(modifier.attribute, "with somewhere to name the attribute")
	assert_not_null(modifier.magnitude, "and a magnitude")
	return document


## The attribute chosen from what the project declares, rather than typed.
##
## Both halves: the catalogue knows the name, and it knows a misspelling of it
## is not one - which is what the picker colours red and what the asset
## validator now reports without anybody opening that row.
func _choose_the_attribute(
	document: GameplayEffectDocument, modifier: GameplayEffectModifier
) -> void:
	var chosen: GameplayAttributeCatalog.Entry = _entry_for(ATTACK)
	assert_not_null(chosen, "the project declares the attribute the author wants")

	document.set_modifier_attribute(0, chosen.as_reference())
	document.set_modifier_amount(0, BUFF_AMOUNT)
	assert_eq(modifier.attribute.attribute_name, ATTACK, "the modifier names it")
	assert_false(
		GameplayAttributeCatalog.is_unknown(modifier.attribute),
		"and the catalogue knows it, so nothing is coloured red"
	)

	var typo: GameplayAttributeRef = GameplayAttributeRef.new()
	typo.attribute_name = &"attakc"
	document.set_modifier_attribute(0, typo)
	assert_false(
		GameplayAssetValidator.validate_effect(document.effect).is_empty(),
		"a misspelling is a finding before anything runs"
	)

	document.set_modifier_attribute(0, chosen.as_reference())
	assert_true(
		GameplayAssetValidator.validate_effect(document.effect).is_empty(),
		"and the effect is clean once it is spelled the way the project declares"
	)


func _entry_for(attribute_name: StringName) -> GameplayAttributeCatalog.Entry:
	for entry: GameplayAttributeCatalog.Entry in GameplayAttributeCatalog.entries():
		if entry.attribute_name == attribute_name:
			return entry
	return null


## `(stunned or immune) and not immune`, nested by the editor's own operations.
##
## Nested rather than flat, because that is what the three operators are for:
## the same three tags under one ALL says something else entirely.
func _nest_the_query(document: GameplayEffectDocument) -> GameplayTagQuery:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var root: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)

	var either: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(
		root, GameplayTagQueryExpression.Operator.ANY
	)
	GameplayTagQueryEdits.add_tag(either, NEW_TAG)
	GameplayTagQueryEdits.add_tag(either, IMMUNE)

	var neither: GameplayTagQueryExpression = GameplayTagQueryEdits.nest(
		root, GameplayTagQueryExpression.Operator.NONE
	)
	GameplayTagQueryEdits.add_tag(neither, IMMUNE)

	assert_eq(
		GameplayTagQueryEdits.rows_of(query).size(), 6,
		"the editor draws the whole tree: three expressions and three tags"
	)

	var requirement: GameplayEffectTargetTagRequirementsComponent = (
		GameplayEffectTargetTagRequirementsComponent.new()
	)
	requirement.application_query = query
	assert_true(document.add_component(requirement), "the effect carries the gate")
	return query


## The project renames a tag, and the asset that named the old one is not
## touched.
##
## The rule with teeth: an asset that still says `Status.Stun` keeps saying it,
## and the runtime resolves it at the door rather than rewriting anybody's file.
func _redirect_the_old_tag() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD_TAG: NEW_TAG}
	assert_eq(
		GameplayTagRedirects.resolve(OLD_TAG, redirects), NEW_TAG,
		"the old name resolves to the one the project has now"
	)

	# And an asset that still names the old one is not touched by finding that
	# out. Authored here rather than loaded, because what is being checked is
	# that resolving writes nothing: the query says afterwards exactly what
	# somebody typed into it.
	var older: GameplayTagQuery = GameplayTagQuery.new()
	var says: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(older)
	GameplayTagQueryEdits.add_tag(says, OLD_TAG)
	GameplayTagRedirects.resolve(OLD_TAG, redirects)

	assert_eq(
		says.tags, [OLD_TAG] as Array[StringName],
		"the query that names the old tag still names it, byte for byte"
	)


## The effect applied, gating on the query the author nested.
func _apply(effect: GameplayEffect) -> ActiveGameplayEffect:
	asc.tags.add(NEW_TAG)
	var before: float = asc.get_attribute_current(ATTACK)

	var applied: ActiveGameplayEffect = asc.apply_gameplay_effect(effect, asc, 1.0)

	assert_not_null(applied, "the gate let it in: the target is stunned and not immune")
	assert_almost_eq(
		asc.get_attribute_current(ATTACK), before + BUFF_AMOUNT, TOLERANCE,
		"and what the editor authored is what the runtime applied"
	)
	return applied


## The four pages, drawn by the game rather than by the editor.
func _inspect_four_pages(applied: ActiveGameplayEffect) -> void:
	var scene: PackedScene = load(GasDebugOverlay.SCENE)
	var overlay: GasDebugOverlay = scene.instantiate()
	add_child_autofree(overlay)

	assert_true(overlay.watch(asc), "the overlay is watching the entity")
	assert_eq(overlay.pages().size(), 4, "and has the four pages the phase names")
	assert_false(Engine.is_editor_hint(), "with no editor anywhere")

	var taken: GasRuntimeSnapshot = overlay.snapshot()
	var said: Array[String] = []
	for index: int in overlay.pages().size():
		assert_true(overlay.show_page(index), "each page is shown")
		for row: GasDebugPage.Row in overlay.pages()[index].rows(taken):
			said.append(row.said())

	var printed: String = LINE_BREAK.join(said)
	assert_true(printed.contains(String(ATTACK)), "the attributes page names the buff")
	assert_true(printed.contains(String(NEW_TAG)), "the tags page names the tag")
	assert_eq(
		String(applied.get_effect_def().resource_name), EFFECT_NAME,
		"the effect on the character is the one that was authored"
	)
	assert_true(
		printed.contains(EFFECT_NAME),
		"and the effects page names it: %s" % printed
	)


## The sample's own area effect, aimed and landed.
##
## Through the sample rather than through a rig, because the sample is what
## somebody copies: a walk that proved the pieces work in an arrangement nobody
## ships would be proving the wrong thing.
func _aim_an_area() -> void:
	var world: SampleWorld = SampleWorld.new()
	add_child_autofree(world)
	world.build()

	var findings: Array[SampleProbe.Finding] = SampleProbe.run(world)
	assert_eq(findings.size(), 6, "the sample demonstrated everything it claims to")
	for finding: SampleProbe.Finding in findings:
		assert_true(finding.held, finding.shown())
#endregion
