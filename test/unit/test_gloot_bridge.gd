## The GLoot bridge: what wearing an item does, and what taking it off undoes.
##
## The claim that matters is not that equipping works. It is that unequipping
## removes exactly what was given and nothing else - which is why the bridge
## keeps a receipt rather than looking the grant up again. A catalogue edited
## while the game ran, or a tag some other source is also holding, breaks the
## look-it-up-again version and leaves the wearer with either too much or too
## little.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const Probe = preload("res://test/fixtures/probe_ability.gd")
const Slot = preload("res://test/fixtures/fake_gloot_slot.gd")
const Item = preload("res://test/fixtures/fake_gloot_item.gd")

const TOLERANCE: float = 0.0001
const SWORD: StringName = &"item.sword"
const SHIELD: StringName = &"item.shield"
const UNKNOWN: StringName = &"item.nothing"
const SWORN: StringName = &"State.Sworn"
const ABILITY_TAG: StringName = &"Ability.Cleave"
## Attack, not health: health is clamped to max_health, so a passive bonus
## there would be swallowed by the ceiling and the test would be measuring the
## clamp rather than the grant.
const ATTACK: StringName = &"attack"
const BONUS: float = 10.0
const START_ATTACK: float = 10.0

var fixture: ASCFixture = null
var slot: FakeGlootSlot = null
var bridge: GlootGasBridge = null

var applied: Array[StringName] = []
var removed: Array[StringName] = []
var rejected: Array[StringName] = []


func before_each() -> void:
	fixture = Fixture.create("Wearer")
	add_child_autofree(fixture.owner)
	fixture.set_base(ATTACK, START_ATTACK)

	slot = Slot.build()
	add_child_autofree(slot)

	bridge = GlootGasBridge.new()
	add_child_autofree(bridge)
	bridge.equipment_applied.connect(_on_applied)
	bridge.equipment_removed.connect(_on_removed)
	bridge.equipment_rejected.connect(_on_rejected)

	applied = []
	removed = []
	rejected = []


func after_each() -> void:
	fixture = null
	slot = null
	bridge = null


#region Building grants
func _on_applied(prototype_id: StringName) -> void:
	applied.append(prototype_id)


func _on_removed(prototype_id: StringName) -> void:
	removed.append(prototype_id)


func _on_rejected(prototype_id: StringName) -> void:
	rejected.append(prototype_id)


## A scene whose root really is an ability.
func _ability_scene() -> PackedScene:
	var ability: ProbeAbility = Probe.build(ABILITY_TAG)
	var scene: PackedScene = PackedScene.new()
	scene.pack(ability)
	ability.free()
	return scene


## And one whose root is not, which the bridge has to notice before granting.
func _plain_scene() -> PackedScene:
	var node: Node = Node.new()
	node.name = "NotAnAbility"
	var scene: PackedScene = PackedScene.new()
	scene.pack(node)
	node.free()
	return scene


func _grant(prototype_id: StringName) -> GlootGasEquipmentGrant:
	var grant: GlootGasEquipmentGrant = GlootGasEquipmentGrant.new()
	grant.prototype_id = prototype_id
	return grant


func _catalog(entries: Array[GlootGasEquipmentGrant]) -> GlootGasEquipmentCatalog:
	var catalog: GlootGasEquipmentCatalog = GlootGasEquipmentCatalog.new()
	catalog.grants = entries
	return catalog


## The ordinary case: one ability, one passive buff, one tag.
func _full_sword() -> GlootGasEquipmentGrant:
	var grant: GlootGasEquipmentGrant = _grant(SWORD)
	grant.abilities = [_ability_scene()]
	grant.passive_effects = [Factory.infinite([Factory.add(ATTACK, BONUS)])]
	grant.direct_tags = [SWORN]
	return grant


func _bind_with(entries: Array[GlootGasEquipmentGrant]) -> bool:
	return bridge.bind(slot, fixture.asc, _catalog(entries))
#endregion


#region Binding
func test_binding_needs_a_slot_an_asc_and_a_catalogue() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_false(bridge.bind(null, fixture.asc, _catalog(entries)), "no slot")
	assert_false(bridge.bind(slot, null, _catalog(entries)), "nobody to equip")
	assert_false(bridge.bind(slot, fixture.asc, null), "nothing to look items up in")


func test_a_slot_freed_before_the_bridge_does_not_take_the_teardown_with_it() -> void:
	# The ordinary teardown order: a scene frees the node the bridge watches,
	# and the bridge beside it goes a moment later. A freed Node is not null,
	# so the old `!= null` guard was true and is_connected() reached a dead
	# instance, taking the shutdown with it.
	# Its own slot, not the fixture's: this one is freed by hand, and the
	# fixture's is freed again by the test runner afterwards.
	var doomed: FakeGlootSlot = Slot.build()
	add_child(doomed)
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(bridge.bind(doomed, fixture.asc, _catalog(entries)), "bound to it")

	doomed.free()
	bridge.unbind()

	assert_null(bridge.target_asc, "the bridge let go instead of crashing")
	# Not also asked to refuse binding to the dead node: GDScript's typed-argument
	# check rejects a freed object before bind() runs, which halts the run under
	# the debugger rather than returning false. That check is the guard there.

func test_binding_to_a_node_that_is_not_a_slot_is_refused() -> void:
	var stranger: Node = Node.new()
	add_child_autofree(stranger)
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_false(
		bridge.bind(stranger, fixture.asc, _catalog(entries)),
		"it has neither the signals nor get_item"
	)


## An ambiguous catalogue is refused while somebody is still looking at it.
func test_a_catalogue_with_a_duplicate_prototype_is_refused() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword(), _full_sword()]
	assert_false(_bind_with(entries), "which of the two would a lookup mean?")


func test_binding_to_a_slot_shaped_node_succeeds() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries), "the double carries the contract the bridge needs")
#endregion


#region Wearing something
func test_equipping_a_known_item_grants_all_three_kinds() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))

	slot.equip(Item.build(SWORD))

	assert_eq(applied, [SWORD] as Array[StringName], "the grant was applied")
	assert_eq(fixture.asc.ability_runtime.specs().size(), 1, "the ability arrived")
	assert_almost_eq(
		fixture.current_of(ATTACK), START_ATTACK + BONUS, TOLERANCE, "the passive buff too"
	)
	assert_true(fixture.asc.has_tag(SWORN), "and the tag")


func test_an_unknown_prototype_is_reported_rather_than_ignored() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))

	slot.equip(Item.build(UNKNOWN))

	assert_eq(rejected, [UNKNOWN] as Array[StringName], "a designer wants to hear about this")
	assert_eq(applied.size(), 0, "and nothing was granted")


## A scene that is not an ability is found before anything reaches the ASC.
func test_a_grant_whose_scene_is_not_an_ability_gives_nothing() -> void:
	var broken: GlootGasEquipmentGrant = _grant(SWORD)
	broken.abilities = [_plain_scene()]
	broken.direct_tags = [SWORN]
	var entries: Array[GlootGasEquipmentGrant] = [broken]
	assert_true(_bind_with(entries))

	slot.equip(Item.build(SWORD))

	assert_eq(rejected, [SWORD] as Array[StringName], "refused")
	assert_false(fixture.asc.has_tag(SWORN), "and the tag it would also have given never landed")
	assert_eq(fixture.asc.ability_runtime.specs().size(), 0, "nor any ability")


## A passive that expires is not a passive. Refused before anything is applied.
func test_a_grant_with_a_non_infinite_passive_gives_nothing() -> void:
	var broken: GlootGasEquipmentGrant = _grant(SWORD)
	broken.passive_effects = [Factory.duration([Factory.add(ATTACK, BONUS)], 5.0)]
	broken.direct_tags = [SWORN]
	var entries: Array[GlootGasEquipmentGrant] = [broken]
	assert_true(_bind_with(entries))

	slot.equip(Item.build(SWORD))

	assert_eq(rejected, [SWORD] as Array[StringName], "an item's effect ends with the item")
	assert_false(fixture.asc.has_tag(SWORN), "and nothing else was given either")
#endregion


#region Taking it off
func test_unequipping_removes_exactly_what_was_given() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))
	slot.equip(Item.build(SWORD))

	slot.clear()

	assert_eq(removed, [SWORD] as Array[StringName], "reported")
	assert_eq(fixture.asc.ability_runtime.specs().size(), 0, "the ability went")
	assert_almost_eq(fixture.current_of(ATTACK), START_ATTACK, TOLERANCE, "the buff went")
	assert_false(fixture.asc.has_tag(SWORN), "and the tag went")


## The ASC counts tag references, so an item takes back only its own.
func test_a_tag_another_source_also_holds_survives_unequipping() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))
	fixture.asc.add_tag(SWORN)
	slot.equip(Item.build(SWORD))

	slot.clear()

	assert_true(fixture.asc.has_tag(SWORN), "the other source still holds it")


func test_clearing_an_already_empty_slot_reports_nothing() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))

	slot.clear()
	slot.clear()

	assert_eq(removed.size(), 0, "there was nothing to take back")


func test_swapping_items_takes_the_first_back_before_giving_the_second() -> void:
	var shield: GlootGasEquipmentGrant = _grant(SHIELD)
	shield.direct_tags = [SWORN]
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword(), shield]
	assert_true(_bind_with(entries))

	slot.equip(Item.build(SWORD))
	slot.equip(Item.build(SHIELD))

	assert_eq(removed, [SWORD] as Array[StringName], "the sword came off first")
	assert_eq(applied, [SWORD, SHIELD] as Array[StringName], "and the shield went on")
	assert_eq(fixture.asc.ability_runtime.specs().size(), 0, "the sword's ability went with it")
	assert_almost_eq(fixture.current_of(ATTACK), START_ATTACK, TOLERANCE, "and its buff too")
	assert_true(fixture.asc.has_tag(SWORN), "while the shield's own tag is held")


## Letting go of the slot must not leave its abilities on the wearer.
func test_unbinding_takes_back_whatever_was_worn() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))
	slot.equip(Item.build(SWORD))

	bridge.unbind()

	assert_eq(removed, [SWORD] as Array[StringName], "taken back on the way out")
	assert_eq(fixture.asc.ability_runtime.specs().size(), 0, "nothing was left behind")
	assert_null(bridge.target_asc, "and the bridge holds nobody")
	assert_null(bridge.catalog, "and nothing to look things up in")


func test_nothing_arrives_after_unbinding() -> void:
	var entries: Array[GlootGasEquipmentGrant] = [_full_sword()]
	assert_true(_bind_with(entries))
	bridge.unbind()
	applied = []

	slot.equip(Item.build(SWORD))

	assert_eq(applied.size(), 0, "the bridge stopped listening")
	assert_eq(slot.item_equipped.get_connections().size(), 0, "and let the connection go")
#endregion
