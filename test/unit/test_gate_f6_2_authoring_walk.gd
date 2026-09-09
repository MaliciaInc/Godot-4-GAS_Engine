## F6.2's gate: one hit, authored the way the phase says a hit is authored, with
## every piece the package added doing its job in the same application.
##
## Each piece has its own tests. This exists because pieces that pass separately
## can still be wrong together: a scoped modifier that leaks into the aggregate
## the buff is already in, a meta attribute cleared before the set that reads it
## has run, a cue scaled by a number the binding never normalised. The walk is
## one application end to end.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const Fixture = preload("res://test/fixtures/asc_fixture.gd")
const Factory = preload("res://test/fixtures/test_effect_factory.gd")
const PolicySet = preload("res://test/fixtures/policy_attribute_set.gd")
const CueManagerScript = preload("res://addons/GAS_Engine/managers/gameplay_cue_manager.gd")
const CueProbe = preload("res://test/fixtures/cue_probe.gd")

const TOLERANCE: float = 0.0001
const CRITICAL: StringName = &"Hit.Critical"
const IMPACT: StringName = &"Cue.Walk.Impact"
const AURA: StringName = &"Cue.Walk.Aura"

var fixture: ASCFixture = null
var asc: AbilitySystemComponent = null
var manager: CueManagerScript = null


## A target that hears about its own cues, which is the interface half of
## F6.2.7: the binding plays AND the target is told, never one instead of the
## other.
class ListeningOwner extends Node3D:
	var heard: Array[StringName] = []

	func handle_gameplay_cue(
		tag: StringName, _event: GameplayCueNotify.Event, _params: GameplayCueParams
	) -> void:
		heard.append(tag)


## The damage calculation the walk is about.
##
## It reads the tags the application carried, reads speed through its own scoped
## adjustment, and writes what it worked out into the meta attribute for the set
## to deal with. Three of the package's pieces, in the order a real calculation
## would use them.
class WalkDamage extends GameplayExecutionCalculation:
	static var heard_critical: bool = false
	static var read_speed: float = 0.0
	static var adjustment: GameplayExecutionScopedModifier = null

	func scoped_modifiers() -> Array[GameplayExecutionScopedModifier]:
		return [adjustment] as Array[GameplayExecutionScopedModifier]

	func execute_in(context: GameplayExecutionContext) -> GameplayExecutionOutput:
		heard_critical = context.passed_in_tags.has(CRITICAL)
		read_speed = context.adjust(
			PolicyAttributeSet.SPEED,
			context.target_asc.get_attribute_current(PolicyAttributeSet.SPEED)
		)
		var output: GameplayExecutionOutput = GameplayExecutionOutput.new()
		output.modifiers.append(
			GameplayExecutionOutput.adding(PolicyAttributeSet.DAMAGE, (read_speed - 100.0) / 2.0)
		)
		return output


func before_each() -> void:
	fixture = Fixture.create("Walked", PolicySet)
	add_child_autofree(fixture.owner)
	asc = fixture.asc
	asc.set_process(false)
	manager = asc.get_node_or_null("/root/GameplayCueManager") as CueManagerScript
	WalkDamage.heard_critical = false
	WalkDamage.read_speed = 0.0
	WalkDamage.adjustment = null


func after_each() -> void:
	manager.remove_all_cues(fixture.owner)
	manager.unbind_cue(IMPACT)
	manager.unbind_cue(AURA)
	manager.catalog.flags.erase(IMPACT)
	manager.catalog.flags.erase(AURA)
	manager._pool.erase(IMPACT)
	manager._pool.erase(AURA)
	fixture = null
	asc = null
	manager = null


#region Getting there
## Bind a template cue to a tag, through the manager's own map.
##
## The real GameplayCueNotifyBurst and GameplayCueNotifyLooping, not a recording
## stand-in: what the walk is checking is that a project gets these without
## writing a script, so a script written here would be checking the wrong thing.
func _bind_template(tag: StringName, cue: GameplayCueNotifyTemplate) -> void:
	var scene: PackedScene = PackedScene.new()
	scene.pack(cue)
	cue.free()
	manager.bind_cue(tag, scene)


func _spark_set() -> GameplayCueEffectSet:
	var placement: GameplayCuePlacement = GameplayCuePlacement.new()
	# Attached, so what it spawns hangs off the body a person is looking at
	# rather than beside it - which is also where the walk goes looking.
	placement.mode = GameplayCuePlacement.Mode.ATTACH_TO_TARGET
	placement.scale_by_magnitude = true
	var made: GameplayCueEffectSet = GameplayCueEffectSet.new()
	var template: Node3D = Node3D.new()
	var scene: PackedScene = PackedScene.new()
	scene.pack(template)
	template.free()
	made.particles = [scene] as Array[PackedScene]
	made.placement = placement
	return made


## The scoped adjustment: the bonus part of the target's own speed, added to
## what the execution reads. An attribute-based magnitude inside a scoped
## modifier, which is both of F6.2.2's and F6.2.3's answers in one place.
func _bonus_of_speed() -> GameplayExecutionScopedModifier:
	var reads: GameplayAttributeBasedMagnitude = GameplayAttributeBasedMagnitude.new()
	reads.capture = Factory.capture_definition(
		GameplayAttributeCaptureDefinition.Actor.TARGET, PolicyAttributeSet.SPEED
	)
	reads.capture.policy = GameplayAttributeCaptureDefinition.Policy.LIVE
	reads.calculation = GameplayAttributeBasedMagnitude.Calculation.BONUS_MAGNITUDE

	var modifier: GameplayExecutionScopedModifier = GameplayExecutionScopedModifier.new()
	modifier.attribute = GameplayAttributeRef.new()
	modifier.attribute.attribute_name = PolicyAttributeSet.SPEED
	modifier.magnitude = reads
	return modifier
#endregion


func test_the_whole_authoring_contract_walks_on_one_hit() -> void:
	var declared: PolicyAttributeSet = fixture.attributes as PolicyAttributeSet
	var listening: ListeningOwner = ListeningOwner.new()
	listening.name = "Body"
	add_child_autofree(listening)
	# The body cues and effects act on, which is what the target interface is
	# implemented on: a game puts that method where its character already is.
	asc.init_ability_actor_info(fixture.owner, listening)

	# 1. A buff on the target, so speed has a bonus part to read.
	Factory.apply(asc, Factory.infinite([Factory.add(PolicyAttributeSet.SPEED, 30.0)]))
	assert_almost_eq(
		fixture.current_of(PolicyAttributeSet.SPEED), 130.0, TOLERANCE, "buffed"
	)

	# 7a. An aura that runs while the buff does.
	var looping: GameplayCueNotifyLooping = GameplayCueNotifyLooping.new()
	looping.looping = _spark_set()
	_bind_template(AURA, looping)
	var aura: ActiveGameplayEffect = Factory.apply(
		asc,
		Factory.with_persistent_cues(
			Factory.infinite([] as Array[GameplayEffectModifier]), [AURA] as Array[StringName]
		)
	)
	assert_true(manager.is_cue_active(listening, AURA), "the aura is running")

	# 5. A burst that scales itself by how much health is left, out of 200.
	var burst: GameplayCueNotifyBurst = GameplayCueNotifyBurst.new()
	burst.burst = _spark_set()
	_bind_template(IMPACT, burst)

	# 2, 3, 4. One hit: told what it was, reading through its own adjustment,
	# writing into an attribute that holds nothing.
	WalkDamage.adjustment = _bonus_of_speed()
	var hit: GameplayEffect = Factory.instant([] as Array[GameplayEffectModifier])
	hit.executions = [WalkDamage.new()] as Array[GameplayExecutionCalculation]
	var binding: GameplayCueBinding = GameplayCueBinding.new()
	binding.cue_tag = IMPACT
	binding.magnitude_attribute = GameplayAttributeRef.new()
	binding.magnitude_attribute.attribute_name = PolicyAttributeSet.HEALTH
	binding.min_level = 0.0
	binding.max_level = 200.0
	hit.cues = [binding] as Array[GameplayCueBinding]

	var spec: GameplayEffectSpec = GameplayEffectSpec.new(
		hit, GameplayEffectContext.new(listening)
	)
	spec.passed_in_tags = [CRITICAL] as Array[StringName]
	asc.apply_effect_spec(spec)

	assert_true(WalkDamage.heard_critical, "2: the calculation was told what the hit was")
	assert_almost_eq(
		WalkDamage.read_speed, 160.0, TOLERANCE, "3: and read speed through its adjustment"
	)
	assert_almost_eq(
		fixture.current_of(PolicyAttributeSet.SPEED),
		130.0,
		TOLERANCE,
		"3: which changed nothing outside the execution"
	)
	assert_almost_eq(declared.absorbed, 30.0, TOLERANCE, "4: the set read the damage")
	assert_almost_eq(
		fixture.base_of(PolicyAttributeSet.DAMAGE),
		0.0,
		TOLERANCE,
		"4: and the attribute is holding nothing afterwards"
	)
	assert_almost_eq(
		fixture.base_of(PolicyAttributeSet.HEALTH), 70.0, TOLERANCE, "4: health took it"
	)

	# 5. The burst scaled by the fraction the binding declared, not by 70.
	var spark: Node3D = _last_spark(listening)
	assert_not_null(spark, "5: the burst played")
	assert_almost_eq(spark.scale.x, 0.35, TOLERANCE, "5: scaled by 70 out of 200")

	# 6. And the target itself was told, beside the binding that played.
	assert_true(listening.heard.has(IMPACT), "6: the target heard its own cue")

	# 7b. The aura stops when the effect behind it does, and nothing is left.
	asc.effects.remove(aura)
	assert_false(manager.is_cue_active(listening, AURA), "7: the aura is over")


## The most recently spawned positioned node under the body.
##
## Off the tree rather than off a cue's ledger, because what the walk is about
## is that something appeared where a person would see it.
func _last_spark(body: Node) -> Node3D:
	var found: Node3D = null
	for child: Node in body.get_children():
		var spatial: Node3D = child as Node3D
		if spatial != null:
			found = spatial
	return found
