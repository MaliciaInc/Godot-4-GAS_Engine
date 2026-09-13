## One aim, from pointing at the ground to the effect landing on the three
## nearest enemies.
##
## Each piece has its own tests. This exists because pieces that pass separately
## can still be wrong together: a preset that drops the place the trace found, a
## reticle drawing an aim the confirm did not take, an application that reaches
## somebody the filter removed. The walk is one aim end to end.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const AttributeSetScript = preload("res://test/fixtures/test_attribute_set.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")

const TOLERANCE: float = 0.0001
const SIZE: float = 1.0
const ENEMY: StringName = &"Team.Enemy"
const HEALTH: StringName = &"health"

## Where the spell is aimed, and the four who are standing near it.
const GROUND: Vector3 = Vector3(10.0, 0.0, 0.0)
const CLOSEST: Vector3 = Vector3(10.5, 0.0, 0.0)
const SECOND: Vector3 = Vector3(12.0, 0.0, 0.0)
const THIRD: Vector3 = Vector3(13.5, 0.0, 0.0)
const FOURTH: Vector3 = Vector3(15.0, 0.0, 0.0)

var caster: StaticBody3D = null
var caster_asc: AbilitySystemComponent = null
var ability: GameplayAbility = null


## The aim a person is moving: told where to point, announcing it, and
## answering on the component's generic confirm.
##
## Its own provider rather than a ground trace, because a trace needs a ray to
## strike something and what this walk is about is the sequence after the spot
## is known. The spot is fed in the way a camera would feed it.
class GroundAim extends GameplayTargetProvider:
	var spot: Vector3 = Vector3.ZERO

	func _aim() -> GameplayAbilityTargetData:
		var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
		data.append_location(spot, Vector3.UP)
		return data


func before_each() -> void:
	caster = _actor("Caster", Vector3.ZERO)
	caster_asc = AbilitySystemLocator.find_for_node(caster)
	# Channelling, because aiming has a middle: an ability that ended the
	# moment it started would have nothing to aim with by the time the
	# person is pointing.
	var channelling: ChannelingAbility = ChannelingAbility.new()
	channelling.ability_tags = [&"Ability.Meteor"] as Array[StringName]
	ability = TestAbilityFactory.give(caster_asc, channelling).per_actor_instance
	ability.try_activate()


func after_each() -> void:
	caster = null
	caster_asc = null
	ability = null


#region Building a world
func _actor(actor_name: String, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = actor_name
	body.position = at
	body.collision_layer = 1

	var component: AbilitySystemComponent = AbilitySystemComponent.new()
	component.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	component.attribute_sets = [AttributeSetScript.new()]
	component.share_attributes = true
	body.add_child(component)

	var holder: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = SIZE
	holder.shape = sphere
	body.add_child(holder)

	add_child_autofree(body)
	return body


func _enemy(actor_name: String, at: Vector3) -> StaticBody3D:
	var body: StaticBody3D = _actor(actor_name, at)
	AbilitySystemLocator.find_for_node(body).add_tag(ENEMY)
	return body


func _reticle_scene() -> PackedScene:
	var template: GameplayTargetReticle3D = GameplayTargetReticle3D.new()
	template.name = "Reticle"
	var scene: PackedScene = PackedScene.new()
	scene.pack(template)
	template.free()
	return scene


## Everything at the aimed spot, that is an enemy, nearest first, first three.
##
## The centre is written onto the sweep from what the aim confirmed, which is
## the seam this walk is about: the provider answers with a place, and the
## preset is what turns a place into a list of people.
func _three_nearest_enemies_at(spot: Vector3) -> GameplayTargetingPreset:
	var sweep: TargetingSelectAoe = TargetingSelectAoe.new()
	sweep.radius = 6.0
	sweep.offset = spot

	var expression: GameplayTagQueryExpression = GameplayTagQueryExpression.new()
	expression.operator = GameplayTagQueryExpression.Operator.ANY
	expression.tags = [ENEMY] as Array[StringName]
	var query: GameplayTagQuery = GameplayTagQuery.new()
	query.root = expression
	var enemies: TargetingFilterByTagQuery = TargetingFilterByTagQuery.new()
	enemies.query = query

	var nearest: TargetingSortByDistance = TargetingSortByDistance.new()
	nearest.keep = 3

	var preset: GameplayTargetingPreset = GameplayTargetingPreset.new()
	preset.tasks = [sweep, enemies, nearest] as Array[GameplayTargetingTask]
	return preset
#endregion


func test_the_whole_targeting_contract_walks_from_a_spot_to_three_victims() -> void:
	var closest: StaticBody3D = _enemy("Closest", CLOSEST)
	var second: StaticBody3D = _enemy("Second", SECOND)
	var third: StaticBody3D = _enemy("Third", THIRD)
	var fourth: StaticBody3D = _enemy("Fourth", FOURTH)
	var ally: StaticBody3D = _actor("Ally", Vector3(10.2, 0.0, 0.0))
	await wait_physics_frames(2)

	# 1. A person points at the ground, and what comes back is a place.
	var aim: GroundAim = GroundAim.new()
	aim.spot = GROUND
	ability.aim_with(aim)

	# 2. Something draws it, and the drawing follows the aim.
	var drawing: AbilityTaskVisualizeTargeting = AbilityTaskVisualizeTargeting.create(
		ability, aim, _reticle_scene(), self
	)
	drawing.start()
	aim.update_preview()
	var reticle: GameplayTargetReticle3D = drawing.reticle as GameplayTargetReticle3D
	assert_eq(reticle.global_position, GROUND, "2: the reticle is on the spot")

	# 3. The person says yes, through the component's own generic confirm.
	var taken: Array[GameplayAbilityTargetData] = []
	aim.confirmed.connect(
		func(data: GameplayAbilityTargetData) -> void: taken.append(data)
	)
	caster_asc.input_confirm()

	assert_eq(taken.size(), 1, "3: the aim was taken once")
	assert_true(taken[0].has_locations(), "3: and it is a place")
	assert_true(drawing.is_finished(), "3: the drawing is over")
	assert_null(drawing.reticle, "3: and nothing is left on screen")

	# 4. The place becomes a list of people: everything within six metres of it,
	#    that is an enemy, nearest to the spot first, the first three.
	var victims: GameplayAbilityTargetData = _three_nearest_enemies_at(GROUND).execute(
		caster_asc
	)

	assert_false(
		victims.get_target_nodes().has(ally), "4: the ally was filtered out"
	)
	assert_false(
		victims.get_target_nodes().has(fourth), "4: and the fourth was left out by the take"
	)
	assert_eq(victims.get_target_nodes().size(), 3, "4: three of them")

	# 5. And the effect lands on exactly those three.
	var landed: GameplayTargetApplicationResult = ability.apply_effect_to_targets(
		Factory.instant([Factory.add(HEALTH, -10.0)]), victims
	)

	assert_eq(landed.applied_count(), 3, "5: it applied to three")
	assert_eq(
		landed.refusal,
		GameplayTargetApplicationResult.Refusal.NONE,
		"5: with nothing to explain"
	)
	for struck: StaticBody3D in [closest, second, third] as Array[StaticBody3D]:
		assert_almost_eq(
			AbilitySystemLocator.find_for_node(struck).get_attribute_current(HEALTH),
			90.0,
			TOLERANCE,
			"5: %s took it" % struck.name
		)
	assert_almost_eq(
		AbilitySystemLocator.find_for_node(fourth).get_attribute_current(HEALTH),
		100.0,
		TOLERANCE,
		"5: and the one the take left out did not"
	)
