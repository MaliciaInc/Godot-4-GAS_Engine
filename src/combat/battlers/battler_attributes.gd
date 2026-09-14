## Everything about a combatant that a number can express.
##
## A battler's health, its resource pool and its offensive and defensive
## standing all live here, and nothing else in the game is allowed to keep a
## second copy. An ability that hits, a status that weakens, a piece of gear
## that hardens - all of them write through GameplayEffects onto these
## attributes, and the engine composes the result.
##
## The distinction that matters: a modifier is a *contribution*, not a write. A
## +5 attack buff does not set `attack` to 15; it registers a contribution the
## engine folds in while the effect lives and withdraws when it ends. Nothing
## has to remember to undo anything, which is why a stack of buffs and debuffs
## expiring in any order still lands on the right number.
##
## @meta_license: MIT
@tool
class_name BattlerAttributes extends AttributeSet

#region Names
## Named so an effect, a cost or a magnitude can point at an attribute without
## retyping the string and getting it subtly wrong.
const HEALTH: StringName = &"health"
const MAX_HEALTH: StringName = &"max_health"
const ENERGY: StringName = &"energy"
const MAX_ENERGY: StringName = &"max_energy"
const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"
const SPEED: StringName = &"speed"
const HIT_CHANCE: StringName = &"hit_chance"
const EVASION: StringName = &"evasion"
#endregion


#region Attributes
## Health and energy are pools: they are spent and restored, and bounded by
## their own maxima. The rest are standings that abilities read to decide how
## hard they land.
@export var health: AttributeData = AttributeData.new(100.0)
@export var max_health: AttributeData = AttributeData.new(100.0)
@export var energy: AttributeData = AttributeData.new(0.0)
@export var max_energy: AttributeData = AttributeData.new(6.0)
@export var attack: AttributeData = AttributeData.new(10.0)
@export var defense: AttributeData = AttributeData.new(10.0)
@export var speed: AttributeData = AttributeData.new(70.0)
@export var hit_chance: AttributeData = AttributeData.new(100.0)
@export var evasion: AttributeData = AttributeData.new(0.0)


## Fresh instances per set. Without this the `@export` defaults are evaluated
## once and every battler in the arena shares one health pool - the whole party
## dies the moment anyone does.
func _init() -> void:
	health = AttributeData.new(100.0)
	max_health = AttributeData.new(100.0)
	energy = AttributeData.new(0.0)
	max_energy = AttributeData.new(6.0)
	attack = AttributeData.new(10.0)
	defense = AttributeData.new(10.0)
	speed = AttributeData.new(70.0)
	hit_chance = AttributeData.new(100.0)
	evasion = AttributeData.new(0.0)
#endregion


#region Bounds
## Asked before a base write lands, so an overkill hit is clamped once at the
## source rather than after several systems have already seen a negative pool.
func pre_attribute_base_change(attribute_name: StringName, proposed_base_value: float) -> float:
	return _bounded(attribute_name, proposed_base_value)


## Asked again after modifiers compose, so a `max_health` buff that expires
## cannot leave `health` standing above the ceiling it just lost.
func pre_attribute_change(attribute_name: StringName, proposed_current_value: float) -> float:
	return _bounded(attribute_name, proposed_current_value)


## Asked after a current value moved, which is when a pool's ceiling can have
## come down under the pool.
##
## The clamp above bounds what is shown, and that is only half: a hit writes the
## base, and a base left standing above a ceiling that dropped is health nobody
## can see. With max health raised to 150 and then lowered again, a battler read
## 100 and still carried 150 underneath - so the next blow of thirty took nothing
## off the bar. The engine names this hook for exactly that, and the base is
## brought down through the component's own write rather than poked, so the
## change is recomposed and announced like any other.
func post_attribute_change(asc: Node, attribute_name: StringName, _old_value: float, new_value: float) -> void:
	var pool: StringName = _pool_under(attribute_name)
	var component: AbilitySystemComponent = asc as AbilitySystemComponent
	if pool == &"" or component == null:
		return
	if component.get_attribute_base(pool) > new_value:
		component.set_attribute_base(pool, new_value)


## The pool a ceiling bounds, or nothing when this attribute is nobody's ceiling.
func _pool_under(ceiling: StringName) -> StringName:
	match ceiling:
		MAX_HEALTH:
			return HEALTH
		MAX_ENERGY:
			return ENERGY
		_:
			return &""


## One rule, asked at both boundaries. Two copies of it would be two chances for
## a pool to be bounded on the way in and unbounded on the way out.
func _bounded(attribute_name: StringName, value: float) -> float:
	match attribute_name:
		HEALTH:
			return clampf(value, 0.0, max_health.current_value)
		ENERGY:
			return clampf(value, 0.0, max_energy.current_value)
		HIT_CHANCE, EVASION:
			# Percentages, and bounded above as well as below: unbounded, they
			# turn a fight into a coin that always lands the same way.
			return clampf(value, 0.0, 100.0)
		_:
			return maxf(value, 0.0)
#endregion
