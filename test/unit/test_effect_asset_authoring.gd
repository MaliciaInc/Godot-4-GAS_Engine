## An effect that lives in a file rather than inside whatever built it.
##
## An effect authored in code belongs to its author. Two abilities that should
## apply the same burn each build their own, and the day the burn changes one of
## them is missed - which is not a bug anybody can see, because both still work.
##
## So an effect can be an asset: one Resource on disk, referenced by everything
## that applies it. What matters is that it is the same Resource all the way
## through - the tool writes a `GameplayEffect`, the inspector edits that object,
## and the runtime applies it - rather than a file the tool describes and
## something else has to interpret. The test that carries that weight is the one
## that edits the loaded asset and applies it: no copy, no parallel factory, no
## second spelling of what an effect is.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const PluginWiring = preload("res://test/fixtures/plugin_wiring.gd")

const SCRATCH: String = "user://gas_engine_test/effect_%d.tres"
const ATTACK: StringName = &"attack"
const TOLERANCE: float = 0.0001

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var made: int = 0
var asset_path: String = ""


func before_each() -> void:
	fixture = Fixture.create("Author")
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	DirAccess.make_dir_recursive_absolute("user://gas_engine_test")


func after_each() -> void:
	_discard()
	fixture = null
	asc = null


#region Getting there
func _fresh() -> String:
	made += 1
	asset_path = SCRATCH % made
	return asset_path


func _discard() -> void:
	if not asset_path.is_empty():
		DirAccess.remove_absolute(asset_path)
	asset_path = ""


func _created() -> GameplayEffect:
	var refusal: String = GameplayEffectAsset.create(_fresh())
	assert_eq(refusal, "", "nothing refused the creation")
	return ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_IGNORE) as GameplayEffect
#endregion


#region What creating writes
## A file that loads back as the thing it claims to be.
func test_creating_an_asset_writes_a_gameplay_effect() -> void:
	var effect: GameplayEffect = _created()

	assert_true(FileAccess.file_exists(asset_path), "the asset is there")
	assert_not_null(effect, "and it loads as a GameplayEffect")
	assert_eq(
		effect.policy,
		GameplayEffect.DurationPolicy.INSTANT,
		"blank, which is the smallest valid effect"
	)


## The whole point: the asset the tool wrote is the object everything else edits
## and applies, with nothing in between.
##
## Authored here the way the inspector authors it - by writing the exported
## field on the loaded Resource - then saved, loaded again, and applied. A tool
## that had written its own description of an effect would break at the second
## of those three steps, and one that kept a parallel copy at the third.
func test_the_asset_is_the_object_the_engine_applies() -> void:
	var effect: GameplayEffect = _created()
	fixture.set_base(ATTACK, 100.0)

	var authored: Array[GameplayEffectModifier] = [Factory.add(ATTACK, 25.0)]
	effect.modifiers = authored
	assert_eq(ResourceSaver.save(effect, asset_path), OK, "the edit was saved")

	var reloaded: GameplayEffect = ResourceLoader.load(
		asset_path, "", ResourceLoader.CACHE_MODE_IGNORE
	) as GameplayEffect
	Factory.apply(asc, reloaded)

	assert_almost_eq(
		fixture.base_of(ATTACK), 125.0, TOLERANCE, "what was authored is what landed"
	)


## Every field the phase names as the minimum is one this asset can author.
func test_every_authored_field_is_one_the_asset_carries() -> void:
	var effect: GameplayEffect = _created()

	assert_eq(
		GameplayEffectAsset.missing_fields(effect),
		[] as Array[StringName],
		"nothing in the minimum is absent"
	)
	assert_eq(
		GameplayEffectAsset.AUTHORED_FIELDS.size(), 10, "and the minimum is the whole list"
	)


## And the check that says so can say no.
##
## A checker whose only observed answer is "nothing missing" might be answering
## that to everything, and it would then bless a GameplayEffect that had quietly
## lost half its surface.
func test_the_check_finds_a_field_that_is_not_there() -> void:
	var absent: Array[StringName] = [&"policy", &"no_such_field_on_an_effect"]

	var found: Array[StringName] = GameplayEffectAsset.missing_fields(
		GameplayEffect.new(), absent
	)

	assert_eq(found, [&"no_such_field_on_an_effect"] as Array[StringName], "it names the one")
#endregion


#region Refusing
## A path Godot cannot resolve, and a path that is not a resource at all.
const ROOTLESS: String = "effects/burn.tres"
const NOT_A_RESOURCE: String = "user://gas_engine_test/burn.gd"


func test_a_path_that_cannot_hold_an_asset_is_refused() -> void:
	assert_eq(
		GameplayEffectAsset.create(ROOTLESS),
		GameplayEffectAsset.INVALID_PATH,
		"nothing can load a path with no root"
	)
	assert_eq(
		GameplayEffectAsset.create(NOT_A_RESOURCE),
		GameplayEffectAsset.INVALID_PATH,
		"and a script is not an effect asset"
	)
	assert_false(FileAccess.file_exists(NOT_A_RESOURCE), "and neither was written")


## Creating over something that is already there is refused, and the file that
## was there is left exactly as it was.
func test_creating_over_an_existing_file_is_refused() -> void:
	_created()
	var before: String = FileAccess.get_file_as_string(asset_path)

	var refusal: String = GameplayEffectAsset.create(asset_path)

	assert_eq(refusal, GameplayEffectAsset.ALREADY_EXISTS % asset_path, "refused, and says why")
	assert_eq(FileAccess.get_file_as_string(asset_path), before, "and left what was there")
#endregion


#region The menu that reaches it
## The plugin is an EditorPlugin and cannot be built headless, so what is
## asserted is its source: the item is added, taken back, and routed through the
## one creator rather than through a second way of writing a `.tres`.
const WIRED: Array = [
	["the item is offered", "add_tool_menu_item(EFFECT_MENU, _ask_for_new_effect)"],
	["and taken back on the way out", "remove_tool_menu_item(EFFECT_MENU)"],
	["it asks where the asset goes", "picker.file_selected.connect(_create_effect_at)"],
	["and creates through the one creator", "GameplayEffectAsset.create(asset_path)"],
	["then hands the person that Resource", "EditorInterface.edit_resource(load(asset_path))"],
]


func test_the_plugin_offers_the_creator_and_takes_it_back() -> void:
	assert_eq(
		PluginWiring.missing(WIRED), [] as Array[String], "every part of it is there"
	)
#endregion
