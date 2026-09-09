## The part a burst and a loop have in common: putting one effect set into the
## world and taking it back out again.
##
## Both templates are the same three steps - spawn what the set names, put it
## where the placement says, and say out loud what this addon will not do
## itself - and the difference between them is only how many sets they own and
## when each one plays. Written once here so the two cannot drift into placing
## things differently.
##
## What this deliberately does not do: move a camera, or decide what a
## controller should feel. Those go out as requests carrying the name the set
## declared, and a game maps them to its own shake and its own device. An addon
## that shook the camera would be an addon that owns the camera.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayCueNotifyTemplate extends GameplayCueNotify

## A set asked for a camera shake, by the name it declared.
signal camera_shake_requested(shake: StringName, params: GameplayCueParams)

## And for haptics, on the same terms.
signal haptics_requested(haptics: StringName, params: GameplayCueParams)

## Everything this cue has put into the world and is still responsible for.
##
## Kept so a loop can stop what it started: a persistent cue that spawned an
## aura and then pooled itself without taking it back would leave the aura on a
## character the effect is no longer on.
var _spawned: Array[Node] = []


## Play one set: its sounds, its particles, its decals, and its two requests.
##
## An empty set is not an error and not a no-op worth commenting on - three of
## a looping cue's four sets are usually empty, and asking first is cheaper than
## spawning a parent for nothing.
func play_set(set: GameplayCueEffectSet, params: GameplayCueParams) -> void:
	if set == null or set.is_empty():
		return

	for stream: AudioStream in set.sounds:
		if stream != null:
			_spawn_sound(stream, set, params)
	for scene: PackedScene in set.particles:
		_spawn_scene(scene, set, params)
	for scene: PackedScene in set.decals:
		_spawn_scene(scene, set, params)

	if set.camera_shake != &"":
		camera_shake_requested.emit(set.camera_shake, params)
	if set.haptics != &"":
		haptics_requested.emit(set.haptics, params)


## Take back everything this cue put into the world.
##
## Called by a loop when it ends and by a burst when it is pooled, because a
## pooled node that kept its children would hand the next playback the last
## one's.
func clear_spawned() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()


## Let go of what was spawned without taking it back.
##
## For the one case where this node cannot be the thing that frees them: a
## looping cue's removal set is spawned as the cue is about to be pooled, and
## a puff of smoke freed in the same frame it appeared is not a puff of smoke.
## They are moved out from under this node, given `seconds` to finish, and
## dropped from the ledger - so pooling this cue leaves them alone and
## something still frees them.
func release_spawned(seconds: float) -> void:
	var tree: SceneTree = get_tree()
	for node: Node in _spawned:
		if not is_instance_valid(node):
			continue
		if node.get_parent() == self:
			var beside: Node = get_parent()
			if beside == null:
				continue
			node.reparent(beside)
		if tree == null:
			# Nothing to schedule against; freeing now beats never.
			node.queue_free()
			continue
		tree.create_timer(seconds).timeout.connect(node.queue_free)
	_spawned.clear()


func finish_cue() -> void:
	clear_spawned()
	super()


## One sound, positioned if there is anywhere to position it.
##
## A 3D player under a 3D target and a plain one otherwise: a 2D game has no
## Node3D to attach to, and a cue that insisted on one would be an addon
## deciding what dimension a project is in.
func _spawn_sound(
	stream: AudioStream, set: GameplayCueEffectSet, params: GameplayCueParams
) -> void:
	var spatial: Node3D = _target_3d(params)
	if spatial == null:
		var flat: AudioStreamPlayer = AudioStreamPlayer.new()
		flat.stream = stream
		_adopt(flat, set, params)
		flat.play()
		return

	var player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	player.stream = stream
	_adopt(player, set, params)
	_place(player, set, params)
	player.play()


func _spawn_scene(
	scene: PackedScene, set: GameplayCueEffectSet, params: GameplayCueParams
) -> void:
	if scene == null:
		return
	var made: Node = scene.instantiate()
	_adopt(made, set, params)
	_place(made, set, params)


## Put a spawned node somewhere it will be found again.
##
## Under the target for anything that follows it, and under the target's own
## parent for anything that must not - so a flame travels with a burning
## character and a crater does not travel with whoever made it.
##
## Not under this cue, which would be the obvious place and is the wrong one:
## GameplayCueNotify is a plain Node, and a Node3D whose nearest parent is not
## a Node3D is the root of its own transform hierarchy - so an effect parented
## here would sit at the world origin no matter what it was played on. Either
## way it stays in this cue's ledger, so this cue is still what frees it.
func _adopt(node: Node, set: GameplayCueEffectSet, params: GameplayCueParams) -> void:
	_spawned.append(node)
	var attached: bool = (
		set.placement == null
		or set.placement.mode == GameplayCuePlacement.Mode.ATTACH_TO_TARGET
	)
	var host: Node = null
	if params != null and params.target != null and is_instance_valid(params.target):
		host = params.target if attached else params.target.get_parent()
	if host == null:
		host = self
	host.add_child(node)


## Apply the placement, when both the thing placed and the thing it is placed
## against are in three dimensions. Nothing to do otherwise, and nothing wrong
## with that: a 2D project authoring a placement is saying something this cue
## cannot act on, and acting on it approximately would be worse than not.
func _place(node: Node, set: GameplayCueEffectSet, params: GameplayCueParams) -> void:
	var moved: Node3D = node as Node3D
	if moved == null:
		return

	var placement: GameplayCuePlacement = set.placement
	var mode: GameplayCuePlacement.Mode = (
		placement.mode if placement != null else GameplayCuePlacement.Mode.AT_TARGET_ORIGIN
	)
	var offset: Vector3 = placement.offset if placement != null else Vector3.ZERO

	var target: Node3D = _target_3d(params)
	var origin: Vector3 = target.global_position if target != null else Vector3.ZERO
	if mode == GameplayCuePlacement.Mode.AT_LOCATION and params != null and params.has_location:
		origin = params.location

	if mode != GameplayCuePlacement.Mode.ATTACH_TO_TARGET:
		moved.global_position = origin + offset
		_scale_by(moved, placement, params)
		return

	# Attached, so the offset is in the target's own frame. Refusing to turn
	# with it means leaving the parent's transform out of this node's
	# altogether, which is what top_level is - and then the position has to
	# be given in world space, because it is no longer relative to anything.
	if placement != null and not placement.follow_rotation:
		moved.top_level = true
		moved.global_position = origin + offset
		moved.global_rotation = Vector3.ZERO
	else:
		moved.position = offset
	_scale_by(moved, placement, params)


## The target as something with a position, or null.
func _target_3d(params: GameplayCueParams) -> Node3D:
	if params == null or params.target == null or not is_instance_valid(params.target):
		return null
	return params.target as Node3D


## Scale by how loud the cue was, when the set asked to be.
##
## The normalised number rather than the raw one, so a cue authored once still
## looks right after somebody rebalances what a big hit is worth - which is
## the whole reason a binding declares the range it reads against.
func _scale_by(
	moved: Node3D, placement: GameplayCuePlacement, params: GameplayCueParams
) -> void:
	if placement == null or not placement.scale_by_magnitude or params == null:
		return
	moved.scale = Vector3.ONE * maxf(params.normalized_magnitude, 0.0)
