## Wait until one attribute crosses a fraction of another.
##
## "Below a quarter health" is the question a design asks, and it is not the
## same as "below 25": max health changes, and a threshold written as a number
## is a threshold that means something different after a level-up. The ratio is
## what the design meant.
##
## Both attributes are watched, because either of them moving changes the
## answer - a heal that raises health crosses the same line a max-health buff
## does.
##
## Watches the owner's own attributes, the way AbilityTaskWaitAttributeThreshold
## beside it does: the ratio a design asks about is the ratio of the character
## running the ability. `target_asc` stays a field for a caller that builds the
## task itself and points it elsewhere before registering it.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AbilityTaskWaitAttributeRatioThreshold extends GameplayAbilityTask

enum Direction { AT_OR_BELOW, AT_OR_ABOVE }

var target_asc: AbilitySystemComponent = null
var numerator: StringName = &""
var denominator: StringName = &""
var ratio: float = 0.5
var direction: AbilityTaskWaitAttributeRatioThreshold.Direction = Direction.AT_OR_BELOW

## The ratio when it crossed, for a waiter that wants to know by how much.
var crossed_at: float = 0.0


static func create(
	ability: GameplayAbility,
	of_attribute: StringName,
	over_attribute: StringName,
	wanted_ratio: float,
	wanted_direction: AbilityTaskWaitAttributeRatioThreshold.Direction = Direction.AT_OR_BELOW
) -> AbilityTaskWaitAttributeRatioThreshold:
	var task: AbilityTaskWaitAttributeRatioThreshold = (
		AbilityTaskWaitAttributeRatioThreshold.new()
	)
	task.owner_ability = ability
	task.numerator = of_attribute
	task.denominator = over_attribute
	task.ratio = wanted_ratio
	task.direction = wanted_direction
	task.target_asc = ability.owner_asc if ability != null else null
	return task


## Checked the moment it starts as well as on every change.
##
## An entity already below the line when the task begins has crossed it as far
## as the design is concerned, and a task that only watched for movement would
## wait for a change that has already happened.
func _on_start() -> void:
	if target_asc == null:
		return
	target_asc.attribute_changed.connect(_on_attribute_changed)
	_check()


func _on_finish() -> void:
	if target_asc == null:
		return
	if target_asc.attribute_changed.is_connected(_on_attribute_changed):
		target_asc.attribute_changed.disconnect(_on_attribute_changed)


func _on_attribute_changed(
	attribute_name: StringName,
	_old_value: float,
	_new_value: float,
	_spec: GameplayEffectSpec
) -> void:
	if attribute_name != numerator and attribute_name != denominator:
		return
	_check()


## A denominator of zero is not a ratio.
##
## Dividing would answer INF, which compares as above every threshold and below
## none - so an entity whose max health is briefly zero would trip every
## "above" task watching it.
func _check() -> void:
	var over: float = target_asc.get_attribute_current(denominator)
	if is_zero_approx(over):
		return

	var now: float = target_asc.get_attribute_current(numerator) / over
	var crossed: bool = now <= ratio if direction == Direction.AT_OR_BELOW else now >= ratio
	if not crossed:
		return
	crossed_at = now
	succeed()
