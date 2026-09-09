## Show what is being aimed at, and take it off the screen afterwards.
##
## The seam between aiming and drawing. A provider works out what is being
## aimed at and announces it; this task is the thing that decides to draw, and
## it is the only thing holding the reticle. A provider that kept one would make
## aiming and drawing one operation, and a headless server would be
## instantiating art.
##
## Ends the way every other task ends, which is the point: an ability that is
## cancelled, aborted, or torn down with its component takes this with it, so a
## reticle left on screen for an ability that is over is not a thing that can
## happen.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskVisualizeTargeting extends GameplayAbilityTask

## What is being aimed, and what is drawing it. The scene is authored by the
## game; nothing here knows or cares what is inside it.
var provider: GameplayTargetProvider = null
var reticle_scene: PackedScene = null

## The instance, while there is one. Null before `start()` and after the task
## ends, which is what makes "is there a reticle on screen" answerable.
var reticle: Node = null

## Where the reticle is put. The ability's avatar's own parent by default, so a
## ground reticle does not travel with whoever is aiming it.
var host: Node = null


## Watch `for_provider` and draw what it announces.
##
## The scene rather than an instance, so this task owns the whole life of the
## thing it draws: handed a live node it would have to guess whether freeing it
## was its business.
static func create(
	ability: GameplayAbility,
	for_provider: GameplayTargetProvider,
	scene: PackedScene,
	into: Node = null
) -> AbilityTaskVisualizeTargeting:
	var task: AbilityTaskVisualizeTargeting = AbilityTaskVisualizeTargeting.new()
	task.owner_ability = ability
	task.provider = for_provider
	task.reticle_scene = scene
	task.host = into
	return task


func _on_start() -> void:
	if provider == null or reticle_scene == null:
		succeed()
		return

	var made: Node = reticle_scene.instantiate()
	var where: Node = host if host != null else _default_host()
	if where == null:
		# Nowhere to put it is not a reason to fail the ability: aiming works
		# perfectly well unseen, which is exactly what it does on a server.
		made.free()
		succeed()
		return

	reticle = made
	where.add_child(reticle)
	provider.preview_changed.connect(_on_preview_changed)
	provider.confirmed.connect(_on_provider_finished)
	provider.cancelled.connect(_on_provider_cancelled)
	# Whatever is already being aimed, so a reticle created mid-preview does not
	# sit at the origin until the next frame moves it.
	_on_preview_changed(provider.previewed)


func _on_finish() -> void:
	if provider != null:
		if provider.preview_changed.is_connected(_on_preview_changed):
			provider.preview_changed.disconnect(_on_preview_changed)
		if provider.confirmed.is_connected(_on_provider_finished):
			provider.confirmed.disconnect(_on_provider_finished)
		if provider.cancelled.is_connected(_on_provider_cancelled):
			provider.cancelled.disconnect(_on_provider_cancelled)
	if reticle != null and is_instance_valid(reticle):
		reticle.queue_free()
	reticle = null


## Hand the aim to whichever kind of reticle this turned out to be.
##
## Duck-typed on the two reticle types rather than on a shared base, because
## there is no shared base to have: a Node2D and a Node3D have nothing in
## common that a `follow` could be declared on.
func _on_preview_changed(data: GameplayAbilityTargetData) -> void:
	if reticle == null or not is_instance_valid(reticle):
		return
	var flat: GameplayTargetReticle2D = reticle as GameplayTargetReticle2D
	if flat != null:
		flat.follow(data)
		return
	var spatial: GameplayTargetReticle3D = reticle as GameplayTargetReticle3D
	if spatial != null:
		spatial.follow(data)


func _on_provider_finished(_data: GameplayAbilityTargetData) -> void:
	succeed()


func _on_provider_cancelled() -> void:
	cancel(GameplayAbilityTask.CancelReason.MANUAL)


## Where a reticle goes when the caller did not say.
##
## Beside the avatar rather than under it, so a ground reticle stays where it
## was put while the person aiming walks around.
func _default_host() -> Node:
	if owner_ability == null or owner_ability.owner_asc == null:
		return null
	var avatar: Node = owner_ability.owner_asc.get_effect_target()
	if avatar == null or not is_instance_valid(avatar):
		return null
	return avatar.get_parent()
