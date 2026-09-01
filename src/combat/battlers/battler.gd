## One combatant.
##
## A battler is a position, a look, and an AbilitySystemComponent. It keeps no
## stats of its own and no list of what it can do: both live in the ASC, which
## is the only thing that composes them. Ask the battler what its attack is and
## it asks the component; there is no second copy to drift.
##
## What a battler still owns is what the ASC has no opinion about: where it
## stands, which way it faces, whether it belongs to the player, and whether the
## cursor may land on it.
##
## @meta_license: MIT
@tool
class_name Battler extends Node2D

## Emitted once this battler's turn is over, however it ended.
signal turn_finished

## Emitted the moment health reaches zero. The battler is already out by then -
## the tag went on first - so a listener never sees a downed battler that still
## reads as a legal target.
signal downed

## Emitted when the cursor's claim on this battler changes.
signal selection_toggled(selected: bool)

const GROUP: StringName = &"_COMBAT_BATTLER_GROUP"

#region Tags
## A battler out of the fight. Abilities that must not run on a corpse block on
## this rather than each re-deriving "health <= 0", and the arena's turn order
## skips whoever carries it.
const DOWNED: StringName = &"State.Downed"

## Held for exactly as long as this battler is resolving its turn.
const ACTING: StringName = &"State.Acting"
#endregion


#region Authoring
## This battler's own numbers. Duplicated into the ASC at ready, so two wolves
## built from the same resource do not share one health pool.
@export var attributes: BattlerAttributes = null

## What this battler can do, as ability scenes granted at ready.
@export var ability_scenes: Array[PackedScene] = []

@export var battler_anim_scene: PackedScene = null:
	set(value):
		battler_anim_scene = value
		_rebuild_anim()

@export var ai_scene: PackedScene = null

@export var is_player: bool = false:
	set(value):
		is_player = value
		if anim != null:
			anim.direction = BattlerAnim.Direction.LEFT if is_player else BattlerAnim.Direction.RIGHT
#endregion


#region Runtime
## The component that owns every number and every ability. Built here rather
## than authored in the scene so no battler can be saved without one.
var asc: AbilitySystemComponent = null

## What `ability_scenes` became once granted, in the same order, so the action
## menu can offer them by index without a second registry.
var granted: Array[GameplayAbilityHandle] = []

var anim: BattlerAnim = null
var ai: CombatAI = null

var is_selectable: bool = true:
	set(value):
		is_selectable = value
		if not is_selectable and is_selected:
			is_selected = false

var is_selected: bool = false:
	set(value):
		if value and not is_selectable:
			return
		if value == is_selected:
			return
		is_selected = value
		selection_toggled.emit(is_selected)
#endregion


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	assert(attributes != null, "Battler '%s' has no attributes assigned." % name)
	add_to_group(GROUP)

	asc = AbilitySystemComponent.new()
	asc.name = "AbilitySystemComponent"
	# Duplicated, not shared: the ASC isolates its sets anyway, and handing it
	# the authored resource directly would let a runtime write reach the file
	# on disk.
	asc.attribute_sets = [attributes.duplicate()] as Array[AttributeSet]
	add_child(asc)

	asc.attribute_changed.connect(_on_attribute_changed)

	for scene: PackedScene in ability_scenes:
		if scene == null:
			continue
		var handle: GameplayAbilityHandle = asc.give_ability(scene)
		if handle.is_valid():
			granted.append(handle)
		else:
			push_error("Battler '%s' could not grant an ability scene." % name)

	if ai_scene != null:
		var instance: Node = ai_scene.instantiate()
		ai = instance as CombatAI
		if ai == null:
			push_error("Battler '%s': ai_scene is not a CombatAI." % name)
			instance.free()
		else:
			add_child(ai)


#region Queries
## Read through the component, never from a field of our own.
func attribute(attribute_name: StringName) -> float:
	return asc.get_attribute_current(attribute_name) if asc != null else 0.0


func is_downed() -> bool:
	return asc != null and asc.has_tag_exact(DOWNED)


## A battler the cursor may land on: it has to be standing, and it has to be
## offering itself.
func is_targetable() -> bool:
	return is_selectable and not is_downed()


## Turn order. Read live, so a speed buff applied mid-fight is felt on the next
## ordering rather than at the next reload.
static func sort_by_speed(a: Battler, b: Battler) -> bool:
	return a.attribute(BattlerAttributes.SPEED) > b.attribute(BattlerAttributes.SPEED)
#endregion


#region Turn
## Resolve one ability against the targets the arena chose for it.
##
## The cost is not deducted here. An ability commits its own through the engine,
## which is what makes an unaffordable action a refusal rather than a battler
## quietly going into debt. And the targets are handed in rather than found: an
## ability that picked its own could not be aimed by a player.
func act(handle: GameplayAbilityHandle, at: Array[Battler]) -> void:
	if asc == null or is_downed():
		turn_finished.emit()
		return

	var spec: GameplayAbilitySpec = asc.ability_runtime.get_spec(handle)
	var ability: BattlerAbility = spec.per_actor_instance as BattlerAbility if spec != null else null
	if ability == null:
		turn_finished.emit()
		return
	ability.targets = at

	asc.add_tag(ACTING)
	# Handle-keyed activation lives on the ability runtime by the component's
	# own stated design: the facade carries the instance-shaped conveniences,
	# the runtime carries the handle-shaped ones.
	var result: GameplayAbilityActivationResult = asc.ability_runtime.try_activate(handle)
	if result.is_ok():
		await asc.ability_runtime_ended
	asc.remove_tag(ACTING)
	turn_finished.emit()
#endregion


func _on_attribute_changed(
	attribute_name: StringName, _old_value: float, new_value: float, _spec: GameplayEffectSpec
) -> void:
	if attribute_name != BattlerAttributes.HEALTH or new_value > 0.0:
		return
	if is_downed():
		return
	# Tag first, signal second. A listener that reacts by re-targeting must not
	# be able to see a battler that is at zero health and still reads as a legal
	# target.
	asc.add_tag(DOWNED)
	is_selectable = false
	downed.emit()


func _rebuild_anim() -> void:
	if not is_inside_tree():
		await ready
	if anim != null:
		anim.queue_free()
		anim = null
	if battler_anim_scene == null:
		return
	var instance: Node = battler_anim_scene.instantiate()
	anim = instance as BattlerAnim
	if anim == null:
		push_warning("Battler '%s': battler_anim_scene is not a BattlerAnim." % name)
		instance.free()
		return
	add_child(anim)
	anim.setup(self, BattlerAnim.Direction.LEFT if is_player else BattlerAnim.Direction.RIGHT)
