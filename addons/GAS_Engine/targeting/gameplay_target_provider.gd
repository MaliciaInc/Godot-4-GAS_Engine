## Choosing a target, as something with a beginning and an end.
##
## Targeting was one call: ask the physics world, get an answer. That is the
## right shape for a fireball that lands where it was aimed and the wrong one
## for everything a person aims by hand - a ground-target circle they drag
## around, a cone they sweep, a unit they click. Those have a middle: the
## ability is waiting, something is being shown, and it ends by being confirmed
## or by being called off.
##
## So a provider has a life. It begins, it previews as often as anybody asks,
## and it finishes exactly once - confirmed or cancelled, never both and never
## neither. An ability that ends while a provider is still previewing cancels
## it, because a provider nobody is waiting on is a provider holding a preview
## on screen for an ability that is over.
##
## `GameplayTargetingService` stays what it is: the physics queries, asked by
## providers. Nothing about input or a camera belongs in it - a service that
## reads a mouse is a service a headless test cannot run, and every physics
## question this engine asks would become unanswerable to prove.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayTargetProvider extends RefCounted

## The preview moved. Emitted as often as somebody asks it to, and never after
## the provider has finished.
signal preview_changed(data: GameplayAbilityTargetData)

## The person chose. Emitted once, with what they chose.
signal confirmed(data: GameplayAbilityTargetData)

## They chose not to. Emitted once, with nothing.
signal cancelled

## Where in its life this provider is.
##
## Closed on purpose: a provider that could be in some other state is one a
## caller has to guess about, and the guess would be made where the ability
## decides whether it still has a target coming.
enum State { IDLE, PREVIEWING, CONFIRMED, CANCELLED }

var state: GameplayTargetProvider.State = State.IDLE

## The ability this is choosing for, while it is choosing.
##
## Held so `update_preview()` can ask the world the ability is in. Dropped when
## the provider finishes: a provider that outlived its ability and still pointed
## at it would keep a freed Node reachable.
var ability: GameplayAbility = null

## The last preview, and what `confirm()` confirms when nothing newer was asked
## for.
var previewed: GameplayAbilityTargetData = null


## Start choosing for `for_ability`.
##
## Beginning twice is not a beginning: a provider already previewing has state
## a second `begin()` would silently discard, and the ability would be waiting
## on a preview nobody is updating.
func begin(for_ability: GameplayAbility) -> void:
	if state != State.IDLE or for_ability == null:
		return
	ability = for_ability
	state = State.PREVIEWING
	previewed = GameplayAbilityTargetData.new()


## Work out what is being aimed at now, announce it, and hand it back.
##
## Answers empty data rather than null when there is nothing to aim at - an
## aim at nothing is a real answer, and a caller that had to check for null
## would be checking on every frame of every preview.
func update_preview() -> GameplayAbilityTargetData:
	if state != State.PREVIEWING:
		return GameplayAbilityTargetData.new()

	previewed = _aim()
	preview_changed.emit(previewed)
	return previewed


## Take what is being previewed. Once.
func confirm() -> void:
	if state != State.PREVIEWING:
		return
	state = State.CONFIRMED
	var taken: GameplayAbilityTargetData = previewed
	_release()
	confirmed.emit(taken)


## Stop, having chosen nothing. Once.
##
## Safe from any state, including one that has already finished: an ability
## ending cancels whatever it was waiting on without first asking whether that
## thing had already answered, and a cancel that threw would make the ordinary
## teardown of every targeted ability a thing to be careful about.
func cancel() -> void:
	if state == State.CONFIRMED or state == State.CANCELLED:
		return
	state = State.CANCELLED
	_release()
	cancelled.emit()


## Whether it is still going.
func is_choosing() -> bool:
	return state == State.PREVIEWING


## Whether what a client says it aimed at is something it could have aimed at.
##
## The seam replication needs and the reason this is on the provider rather than
## on the ability: the machine that owns the game has to be able to check a
## claim without having been there for the aiming. The default takes nothing on
## trust that it cannot verify - a target with nothing in it is refused, and so
## is one naming something that is no longer in the tree.
##
## A provider that can say more overrides this. Range, line of sight and
## cooldown are its own questions, and it is the only thing that knows them.
func validate_authoritative(
	data: GameplayAbilityTargetData, source_asc: AbilitySystemComponent
) -> bool:
	if data == null or source_asc == null or not data.has_targets():
		return false
	for node: Node in data.get_target_nodes():
		if node == null or not is_instance_valid(node):
			return false
	return true


## What this provider aims at. Overridden by every real one.
##
## Empty here rather than abstract: the base is a usable provider that aims at
## nothing, which is what a test of the lifecycle wants and what an ability with
## no aiming yet behaves as.
func _aim() -> GameplayAbilityTargetData:
	return GameplayAbilityTargetData.new()


#region What the ability is aiming from
## The component doing the aiming, for the filters that ask whose side a hit is
## on.
func source_asc() -> AbilitySystemComponent:
	return ability.owner_asc if ability != null else null


## The body the ability acts through, which is what decides which world it aims
## in. Read from the ability rather than handed in: an ability aims in the world
## it is in, and a provider given a different one can hit something on another
## map.
func avatar() -> Node:
	var component: AbilitySystemComponent = source_asc()
	return component.get_effect_target() if component != null else null


## The 2D world the ability is acting in, or null when it is acting in none.
func world_2d() -> World2D:
	var acting_through: CanvasItem = avatar() as CanvasItem
	return acting_through.get_world_2d() if acting_through != null else null


## And the 3D one. Both live here for the reason GameplayTargetingService keeps
## its own pair together: Godot has two physics servers with no common base, so
## an addon supporting both mirrors them, and mirroring them in one place is one
## thing to keep true rather than four.
func world_3d() -> World3D:
	var acting_through: Node3D = avatar() as Node3D
	return acting_through.get_world_3d() if acting_through != null else null
#endregion


## Let go of the ability, whichever way this ended.
func _release() -> void:
	ability = null
