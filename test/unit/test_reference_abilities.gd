## The six abilities that ship with the engine, held to both halves of what they
## are for: a person can read them, and the Composer can open them.
##
## They were written by hand first and opened in the Composer afterwards, in that
## order and never the other. An example bent into a shape the tool already
## handles proves nothing about the tool - the exam only means something if the
## file was written the way a person writes one and the tool had to cope.
##
## It did not cope, the first time. Three of the six would not open at all, and
## what those three had in common turned out to be a call in an argument list, a
## statement wrapped across lines, and a property being set - which is to say,
## ordinary GDScript. The subset was wrong, not the files.
##
## Nothing here depends on a game. Every one of these runs against a plain ASC
## fixture, which is the same claim the engine makes about itself.
##
## @meta_license: MIT
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const AbilityFactory = preload("res://test/fixtures/test_ability_factory.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")

const REFERENCE: String = "res://addons/GAS_Engine/reference/%s.gd"
const ABILITIES: Array[String] = [
	"instant_damage", "timed_buff", "sweeping_volley",
	"costly_strike", "confirmed_blast", "cued_dash",
]

const HEALTH: StringName = &"health"
const MANA: StringName = &"mana"
const ATTACK: StringName = &"attack"
const DAMAGE: float = -12.0
const BLESSING: float = 6.0
const BLESSING_SECONDS: float = 30.0
const COST: float = -20.0
const START_MANA: float = 50.0
const START_HEALTH: float = 100.0
const COOLDOWN_TAG: StringName = &"Cooldown.Reference"
const COOLDOWN_SECONDS: float = 8.0
const LAUNCH: StringName = &"Cue.Dash.Launch"
const LANDING: StringName = &"Cue.Dash.Land"
const SWEEP_RADIUS: float = 64.0
const BODY_RADIUS: float = 8.0
const TOLERANCE: float = 0.0001
const TASK: StringName = &"GameplayAbilityTask"

var caster: ASCFixture = null


func before_each() -> void:
	caster = Fixture.create("Caster")
	add_child_autofree(caster.owner)
	caster.set_base(MANA, START_MANA)


func after_each() -> void:
	caster = null


#region What the files say
func _path(ability_name: String) -> String:
	return REFERENCE % ability_name


func _source(ability_name: String) -> String:
	return FileAccess.get_file_as_string(_path(ability_name))


func _graph(ability_name: String) -> ComposerGraph:
	return ComposerReader.read(_source(ability_name), _path(ability_name))


## The exam itself. Six files a person wrote, and the tool opens all of them.
func test_the_composer_opens_every_reference_ability() -> void:
	for ability_name: String in ABILITIES:
		var graph: ComposerGraph = _graph(ability_name)

		assert_true(
			graph.is_editable(), "%s: %s" % [ability_name, graph.blocked_reason()]
		)
		assert_gt(graph.nodes.size(), 0, "%s draws something" % ability_name)


## Every line of every body belongs to exactly one node.
##
## The check that a graph is a view of the file rather than a summary of it. A
## line nothing claims is a line the canvas does not show, and a line two nodes
## claim is a line a save would write twice.
func test_no_line_of_a_reference_ability_is_lost_or_claimed_twice() -> void:
	for ability_name: String in ABILITIES:
		var lines: PackedStringArray = _source(ability_name).split("\n")
		var body: ComposerSpan = ComposerSubset.body_span(lines)
		var claimed: Dictionary[int, StringName] = {}

		for node: ComposerNode in _graph(ability_name).nodes:
			for line: int in range(node.span.first_line, node.span.last_line + 1):
				assert_false(
					claimed.has(line), "%s line %d is claimed once" % [ability_name, line]
				)
				claimed[line] = node.id

		for line: int in range(body.first_line, body.last_line + 1):
			assert_true(
				claimed.has(line), "%s line %d belongs to a node" % [ability_name, line]
			)


## Opening and saving without editing gives the file back byte for byte.
##
## The whole promise in one assertion. Everything else the Composer does is
## worthless if opening a person's ability can cost them a line of it, and the
## six files here are the only inputs to this that were not written to be easy.
func test_saving_an_unedited_reference_ability_changes_nothing() -> void:
	for ability_name: String in ABILITIES:
		var source: String = _source(ability_name)
		var graph: ComposerGraph = ComposerReader.read(source, _path(ability_name))

		var saved: ComposerWriter.Result = ComposerWriter.apply(graph, source)

		assert_true(saved.is_ok(), "%s: %s" % [ability_name, saved.refusal])
		assert_eq(saved.text, source, "%s came back byte for byte" % ability_name)


## The calls on the ability system are drawn as the calls they are.
##
## `owner_asc.apply_gameplay_effect(...)` is how two thirds of the catalog is
## actually written, and until the receiver was resolved none of it matched: the
## node was keyed by `owner_asc.apply_gameplay_effect`, which no catalog has ever
## heard of, so every argument on the card was numbered instead of named.
func test_a_call_on_the_ability_system_is_named_by_the_catalog() -> void:
	var graph: ComposerGraph = _graph("timed_buff")
	var applied: ComposerNode = null
	for node: ComposerNode in graph.nodes:
		if node.type_id == &"apply_gameplay_effect":
			applied = node

	assert_not_null(applied, "the call was found by its method, not its receiver")
	assert_eq(applied.receiver, "owner_asc", "and the receiver was kept")
	assert_eq(applied.title, "Apply Gameplay Effect", "named for what it does")
	assert_eq(applied.fields[0].label, "Effect", "with the engine's own argument names")
	assert_eq(applied.fields[2].label, "Effect Level", "all three of them")
#endregion


#region What the catalog claims about them
## Every call the catalog says suspends returns a task.
##
## A task is the thing an ability waits on, so that is what suspending looks
## like from the outside. The list is a decision and stays a decision - a game
## answers it for its own calls - but the engine's half of it is held against the
## engine. `apply_effect_to_targets` was on the list and returns a result: the
## card said `await` over a call that does not suspend, and a node placed from
## the palette would have printed one into somebody's file.
func test_every_call_the_catalog_says_suspends_returns_a_task() -> void:
	for entry: ComposerCatalog.Entry in ComposerCatalog.all().values():
		var returned: StringName = _returns(entry)
		assert_eq(
			entry.awaits, ComposerTypes.inherits(returned, TASK),
			"%s returns %s" % [entry.type_id, returned]
		)


## What a catalog entry's method gives back, read off the engine.
func _returns(entry: ComposerCatalog.Entry) -> StringName:
	var script: GDScript = load(entry.source) as GDScript
	for described: Dictionary in script.get_script_method_list():
		var name: String = described["name"]
		if StringName(name) != entry.type_id:
			continue
		var returned: Dictionary = described["return"]
		var declared: String = returned["class_name"]
		return StringName(declared)
	return &""
#endregion


#region And every one of them plays
func _instance(ability_name: String, fields: Dictionary) -> GameplayAbility:
	var ability: GameplayAbility = (load(_path(ability_name)) as GDScript).new()
	for field: String in fields:
		ability.set(field, fields[field])
	var spec: GameplayAbilitySpec = AbilityFactory.give(caster.asc, ability)
	return spec.per_actor_instance


func _damage() -> GameplayEffect:
	return Factory.instant([Factory.add(HEALTH, DAMAGE)])


func _victim(victim_name: String) -> ASCFixture:
	var made: ASCFixture = Fixture.create(victim_name)
	add_child_autofree(made.owner)
	made.set_base(HEALTH, START_HEALTH)
	return made


func _targets(nodes: Array[Node]) -> GameplayAbilityTargetData:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_overlap(nodes)
	return data


func test_instant_damage_pays_asks_and_lands() -> void:
	var ability: GameplayAbility = _instance("instant_damage", {"damage": _damage()})
	var victim: ASCFixture = _victim("Victim")

	ability.try_activate()
	assert_true(ability.is_active, "it holds, waiting to be told where")

	ability.submit_target_data(_targets([victim.owner]))

	assert_almost_eq(
		victim.base_of(HEALTH), START_HEALTH + DAMAGE, TOLERANCE, "the target took it"
	)
	assert_false(ability.is_active, "and the ability finished")


func test_the_timed_buff_leaves_something_running_behind_it() -> void:
	var blessing: GameplayEffect = Factory.duration(
		[Factory.add(ATTACK, BLESSING)], BLESSING_SECONDS
	)
	var ability: GameplayAbility = _instance("timed_buff", {"blessing": blessing})
	var before: float = caster.current_of(ATTACK)

	ability.try_activate()

	assert_almost_eq(
		caster.current_of(ATTACK), before + BLESSING, TOLERANCE, "the blessing is on"
	)
	assert_false(ability.is_active, "and the ability did not stay to watch it")


func test_the_volley_finds_its_own_targets_in_the_world() -> void:
	var caster_body: StaticBody2D = _body("Caster2D", Vector2.ZERO)
	var near: ASCFixture = _in_world("Near", Vector2(SWEEP_RADIUS * 0.5, 0.0))
	var far: ASCFixture = _in_world("Far", Vector2(SWEEP_RADIUS * 8.0, 0.0))
	await wait_physics_frames(2)

	var component: AbilitySystemComponent = _asc_of(caster_body)
	var ability: GameplayAbility = (
		load(_path("sweeping_volley")) as GDScript
	).new()
	ability.set("damage", _damage())
	ability.set("radius", SWEEP_RADIUS)
	var spec: GameplayAbilitySpec = AbilityFactory.give(component, ability)

	spec.per_actor_instance.try_activate()

	assert_almost_eq(
		near.base_of(HEALTH), START_HEALTH + DAMAGE, TOLERANCE, "the one inside the circle"
	)
	assert_almost_eq(far.base_of(HEALTH), START_HEALTH, TOLERANCE, "and not the one outside")


func test_the_costly_strike_refuses_rather_than_half_paying() -> void:
	var ability: GameplayAbility = _instance(
		"costly_strike",
		{"damage": _damage(), "costs": _mana_cost(), "cooldown_effect": _cooldown()}
	)
	caster.set_base(MANA, 0.0)

	ability.try_activate()

	assert_false(ability.is_active, "it declined")
	assert_almost_eq(caster.base_of(MANA), 0.0, TOLERANCE, "having charged nothing")
	assert_false(caster.asc.has_tag(COOLDOWN_TAG), "and started nothing")


func test_the_costly_strike_charges_once_when_it_can_afford_itself() -> void:
	var ability: GameplayAbility = _instance(
		"costly_strike",
		{"damage": _damage(), "costs": _mana_cost(), "cooldown_effect": _cooldown()}
	)
	var victim: ASCFixture = _victim("Struck")

	ability.try_activate()
	ability.submit_target_data(_targets([victim.owner]))

	assert_almost_eq(
		caster.base_of(MANA), START_MANA + COST, TOLERANCE, "charged exactly once"
	)
	assert_true(caster.asc.has_tag(COOLDOWN_TAG), "and on cooldown")
	assert_almost_eq(
		victim.base_of(HEALTH), START_HEALTH + DAMAGE, TOLERANCE, "and it landed"
	)


## The cost is committed after the confirmation, so a spell called off between
## the two waits leaves nothing behind.
func test_the_confirmed_blast_charges_nothing_until_it_is_confirmed() -> void:
	var ability: GameplayAbility = _instance(
		"confirmed_blast", {"blast": _damage(), "costs": _mana_cost()}
	)
	var victim: ASCFixture = _victim("Blasted")

	ability.try_activate()
	ability.submit_target_data(_targets([victim.owner]))

	assert_true(ability.is_active, "aimed, and still waiting to be told to fire")
	assert_almost_eq(caster.base_of(MANA), START_MANA, TOLERANCE, "nothing charged yet")

	caster.asc.ability_local_input_pressed(ability.get_input_id())

	assert_almost_eq(caster.base_of(MANA), START_MANA + COST, TOLERANCE, "now it is")
	assert_almost_eq(
		victim.base_of(HEALTH), START_HEALTH + DAMAGE, TOLERANCE, "and it landed"
	)


func test_the_dash_says_something_at_both_ends() -> void:
	var manager: CueManagerScript = (
		caster.asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	)
	CueProbe.install(manager, LAUNCH)
	CueProbe.install(manager, LANDING)

	var haste: GameplayEffect = Factory.duration([Factory.add(ATTACK, BLESSING)], 1.0)
	var ability: GameplayAbility = _instance(
		"cued_dash", {"haste": haste, "travel_time": 0.02}
	)

	ability.try_activate()
	assert_eq(
		CueProbe.executions(manager, caster.owner, LAUNCH), 1, "it announced the launch"
	)
	assert_eq(
		CueProbe.executions(manager, caster.owner, LANDING), 0, "and had not landed yet"
	)

	await wait_seconds(0.1)

	assert_eq(
		CueProbe.executions(manager, caster.owner, LANDING), 1, "and then it landed"
	)
	assert_false(ability.is_active, "and was done")

	CueProbe.uninstall(manager, LAUNCH)
	CueProbe.uninstall(manager, LANDING)
#endregion


#region A world to sweep
func _shape() -> CollisionShape2D:
	var holder: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = BODY_RADIUS
	holder.shape = circle
	return holder


func _body(body_name: String, at: Vector2) -> StaticBody2D:
	var body: StaticBody2D = StaticBody2D.new()
	body.name = body_name
	body.position = at
	body.add_child(_shape())
	add_child_autofree(body)
	return body


func _in_world(victim_name: String, at: Vector2) -> ASCFixture:
	var made: ASCFixture = Fixture.create(victim_name)
	var body: StaticBody2D = _body(victim_name, at)
	made.owner.remove_child(made.asc)
	body.add_child(made.asc)
	made.owner.free()
	made.owner = body
	made.set_base(HEALTH, START_HEALTH)
	return made


func _asc_of(body: Node) -> AbilitySystemComponent:
	var made: ASCFixture = Fixture.create("CasterComponent")
	made.owner.remove_child(made.asc)
	body.add_child(made.asc)
	made.owner.free()
	made.owner = body
	return made.asc
#endregion


#region Authoring
func _mana_cost() -> Array[GameplayAbilityCost]:
	var cost: GameplayAbilityCost = GameplayAbilityCost.new()
	cost.mode = GameplayAbilityCost.Mode.ABSOLUTE
	cost.target_attribute = MANA
	cost.amount = GameplayScalableFloat.new()
	cost.amount.value = absf(COST)
	return [cost] as Array[GameplayAbilityCost]


func _cooldown() -> GameplayEffect:
	var effect: GameplayEffect = Factory.duration([], COOLDOWN_SECONDS)
	return Factory.granting(effect, [COOLDOWN_TAG] as Array[StringName])
#endregion
