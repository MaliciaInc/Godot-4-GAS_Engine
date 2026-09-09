## A character in this sample: a node, an ability system, and a loadout.
##
## The whole of what a game has to write to put this engine on something. The
## abilities are not known to this file by name beyond the three doors below,
## and nothing here reaches into the runtime: it grants a set, and it activates
## by handle.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleHero extends Node3D

## The component everything else in this sample talks to.
var asc: AbilitySystemComponent = null

## What this character was given, kept so it can be taken back in one call.
var loadout: GameplayAbilitySetHandles = null


func _ready() -> void:
	if asc == null:
		equip()


## Build the ability system and give it the loadout.
##
## Called from `_ready()` for a character placed in a scene, and directly by a
## test that wants one without a frame passing.
func equip() -> void:
	if asc != null:
		return
	asc = AbilitySystemComponent.new()
	asc.name = String(AbilitySystemLocator.ASC_CHILD_NAME)
	# One instance shared with this node rather than a deep copy, so what the
	# overlay reads is what the effects moved.
	asc.share_attributes = true
	add_child(asc)
	loadout = SampleLoadout.built().grant(asc)


## Take the whole loadout off again, in one call.
func unequip() -> void:
	if loadout != null:
		loadout.take_back()
	loadout = null


#region The three things this character can do
## Hit somebody, now.
##
## The victim travels as target data on the activation, which is how an ability
## that lands on the frame it was pressed is aimed: there is no middle for a
## provider to happen in.
func strike(victim: Node) -> GameplayAbilityActivationResult:
	var data: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	data.append_node(victim)
	return _activate(SampleBasicAttack.TAG, data)


## Start channelling, and stay channelling until something ends it.
func channel() -> GameplayAbilityActivationResult:
	return _activate(SampleChannel.TAG, null)


## Start aiming a slam. It lands when a spot is confirmed.
func aim_slam() -> GameplayAbilityActivationResult:
	return _activate(SampleGroundSlam.TAG, null)
#endregion


## The instance behind one of this character's grants, or null.
##
## By tag rather than by handle, because a tag is what the game calls the
## ability and a handle is what the engine calls the grant.
func ability_tagged(tag: StringName) -> GameplayAbility:
	var spec: GameplayAbilitySpec = _spec_tagged(tag)
	return spec.per_actor_instance if spec != null else null


func _spec_tagged(tag: StringName) -> GameplayAbilitySpec:
	if asc == null:
		return null
	for spec: GameplayAbilitySpec in asc.get_ability_specs():
		if spec.definition.ability_tags.has(tag):
			return spec
	return null


## Start one of this character's abilities, aimed at `data` when there is any.
func _activate(
	tag: StringName, data: GameplayAbilityTargetData
) -> GameplayAbilityActivationResult:
	var spec: GameplayAbilitySpec = _spec_tagged(tag)
	if spec == null:
		return GameplayAbilityActivationResult.new()

	var context: GameplayAbilityActivationContext = null
	if data != null:
		context = GameplayAbilityActivationContext.new()
		context.effect_context = GameplayEffectContext.new(self)
		context.effect_context.target_data = data
	return asc.try_activate_ability_handle(spec.handle, context)
