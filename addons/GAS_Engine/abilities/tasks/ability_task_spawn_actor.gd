## Put something in the world, and own it until the ability is done with it.
##
## The half a bare `instantiate()` leaves out. A turret, a totem, a summoned
## wall: an ability that spawns one and then ends leaves it there, and an
## ability that is cancelled half way through leaves it there having done
## nothing. Whether it should outlive the ability is a design decision, so it
## is `keep_on_finish` and not an accident.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskSpawnActor extends GameplayAbilityTask

var scene: PackedScene = null

## Where it goes. The ability's avatar's parent when nobody said otherwise,
## which is the world the ability is acting in.
var into: Node = null

## Whether what was spawned stays when this task ends.
##
## False is the safe default: a task cancelled before it finished spawned
## something nobody asked for, and leaving it is how a cancelled cast litters
## the level with turrets.
var keep_on_finish: bool = false

## What was spawned, for whoever asked for it.
var spawned: Node = null

## It exists.
##
## A signal rather than the task finishing, and the difference is what the task
## is for: finishing is what releases what it owns, so a task that ended the
## moment it spawned would take the thing back out on the same frame it put it
## in. It stays open holding what it made, and the ability ending is what closes
## it - which is the ownership this exists to give.
signal spawned_ready(node: Node)


static func create(
	ability: GameplayAbility, spawned_scene: PackedScene, parent: Node = null
) -> AbilityTaskSpawnActor:
	var task: AbilityTaskSpawnActor = AbilityTaskSpawnActor.new()
	task.owner_ability = ability
	task.scene = spawned_scene
	task.into = parent
	return task


func _on_start() -> void:
	var parent: Node = into if into != null else _default_parent()
	if scene == null or parent == null:
		cancel(GameplayAbilityTask.CancelReason.ABILITY_ABORTED)
		return

	spawned = scene.instantiate()
	parent.add_child(spawned)
	spawned_ready.emit(spawned)


## Take it back out unless the ability said to keep it.
func _on_finish() -> void:
	if spawned == null or keep_on_finish:
		return
	if is_instance_valid(spawned):
		spawned.queue_free()
	spawned = null


func _default_parent() -> Node:
	if owner_ability == null or owner_ability.owner_asc == null:
		return null
	var avatar: Node = owner_ability.owner_asc.get_effect_target()
	return avatar.get_parent() if avatar != null else null
