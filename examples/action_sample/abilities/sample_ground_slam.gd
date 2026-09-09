## An area effect the player puts somewhere and sees before committing to it.
##
## The three pieces F6.3 ships, wired together and nothing else: a provider that
## lets somebody choose a spot, a reticle that draws what the spot would cover,
## and a preset that says what the spot then selects. There is no targeting code
## in this file - only the decision of which pieces, and what happens to whoever
## the preset picked.
##
## It outlives its activation function because aiming has a middle: the ability
## is up while the player is choosing, and ends when they confirm or when
## something cancels them.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleGroundSlam extends GameplayAbility

## What this ability is called, said once.
##
## The node's name and the key a loadout asks for are the same word, and
## two spellings of it is a loadout that silently grants nothing.
const NAME: StringName = &"SampleGroundSlam"

const TAG: StringName = &"Ability.Sample.Slam"

## Who it landed on, in the order the preset put them. Read by the probe.
var struck: Array[Node] = []

## Where it landed, once it has.
var landed_at: Vector3 = Vector3.ZERO

## The ring on screen while somebody is choosing. Freed when the ability ends,
## because a preview left up for an ability that is over is the bug the whole
## provider lifecycle exists for.
var _reticle: GameplayTargetReticle3D = null


static func build() -> SampleGroundSlam:
	var ability: SampleGroundSlam = SampleGroundSlam.new()
	ability.name = String(NAME)
	ability.ability_name = "Slam"
	ability.ability_tags = [TAG]
	ability.auto_end_on_activate_return = false
	# Staggered characters do not slam. One query rather than a check inside the
	# activation, so the ability answers `can_activate` honestly to a UI as well.
	ability.activation_blocked_query = _while_staggered()
	# Predicted, because the aiming is the ability: a player who cannot see
	# the ring until the server says so is a player aiming at nothing. Where
	# it lands is still the authority's to decide - the spot travels as
	# target data and is checked there.
	ability.net_execution_policy = NetExecutionPolicy.LOCAL_PREDICTED
	return ability


## Whether somebody is currently choosing where this lands.
func is_aiming() -> bool:
	return is_active and _reticle != null


func on_granted() -> void:
	if not ability_ended.is_connected(_on_ended):
		ability_ended.connect(_on_ended)


## Start aiming, and show what is being aimed.
##
## The provider is handed to `aim_with`, which connects its confirmation to
## this ability's own `submit_target_data` - so the confirm arrives at
## `on_target_data` below without this file knowing a provider was involved.
func _activate_ability() -> bool:
	struck.clear()
	if not commit_ability().is_ok():
		return false

	_reticle = SampleTargeting.slam_reticle()
	var avatar: Node = owner_asc.get_effect_target()
	if avatar != null:
		avatar.add_child(_reticle)

	aim_with(SampleTargeting.slam_provider())

	# One readable sequence rather than a callback: the task is the ability's
	# side of the handover, and the provider's confirmation arrives through it
	# without this file knowing a provider was involved.
	var waiting: AbilityTaskWaitTargetData = wait_target_data()
	await waiting.completed()
	_land(waiting.target_data)
	return true


## What happens where the player put it.
##
## The confirmed data says where; the preset says who. They are separate
## because a spot with nobody standing in it is still a legal slam, and an
## ability that answered "who" from the aim alone could not tell the difference.
func _land(data: GameplayAbilityTargetData) -> void:
	if not is_active or data == null:
		end_ability()
		return
	for hit: GameplayTargetHit in data.get_all_hits():
		if hit.has_position:
			landed_at = hit.position_3d
			break
	if _reticle != null:
		_reticle.follow(data)

	var selected: GameplayAbilityTargetData = SampleTargeting.slam_preset().execute(owner_asc)
	var victims: GameplayAbilityTargetData = _joined(data, selected)
	if victims.has_targets():
		apply_effect_to_targets(SampleEffects.slam(), victims)
		apply_effect_to_targets(SampleEffects.stagger(), victims)
		struck.assign(victims.get_target_nodes())

	execute_cue(SampleCues.SLAM_IMPACT)
	end_ability()


## Everybody either half found, each of them once.
##
## The aim can carry targets - a game that already knows who it means - and the
## preset finds whoever is standing in the circle. Both count, and somebody in
## both is still one victim.
static func _joined(
	aimed: GameplayAbilityTargetData, selected: GameplayAbilityTargetData
) -> GameplayAbilityTargetData:
	var joined: GameplayAbilityTargetData = GameplayAbilityTargetData.new()
	for node: Node in aimed.get_target_nodes():
		joined.append_node(node)
	if selected != null:
		for node: Node in selected.get_target_nodes():
			joined.append_node(node)
	return joined


## A query for "is staggered right now", built where the ability declares it.
static func _while_staggered() -> GameplayTagQuery:
	var query: GameplayTagQuery = GameplayTagQuery.new()
	var expression: GameplayTagQueryExpression = GameplayTagQueryEdits.ensure_root(query)
	GameplayTagQueryEdits.set_operator(expression, GameplayTagQueryExpression.Operator.ANY)
	GameplayTagQueryEdits.add_tag(expression, SampleEffects.STAGGERED)
	return query


func _on_ended(_was_cancelled: bool) -> void:
	if _reticle != null and is_instance_valid(_reticle):
		_reticle.queue_free()
	_reticle = null
