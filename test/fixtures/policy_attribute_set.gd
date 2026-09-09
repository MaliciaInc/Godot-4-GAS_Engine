## An attribute set that answers the two questions F6.2.4 added: how several
## contributions of one kind combine, and which of its attributes is a message
## rather than a store.
##
## Its own set rather than more fields on TestAttributeSet, which the whole
## suite is built on: a policy other than ALL on an attribute every other test
## uses would change what those tests are measuring, and a meta attribute that
## clears itself would be a stranger surprise still.
##
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name PolicyAttributeSet extends AttributeSet

const SPEED: StringName = &"speed"
const HEALTH: StringName = &"health"
const DAMAGE: StringName = &"damage"

## What a character moves at, and what it has left.
@export var speed: AttributeData = AttributeData.new(100.0)
@export var health: AttributeData = AttributeData.new(100.0)

## A message, not a store: an effect writes into it so this set can read it,
## decide what it means, and be finished with it.
@export var damage: AttributeData = AttributeData.new(0.0)

## Which policy `speed` answers with, set by the test that is asking.
##
## A field rather than three subclasses, because the thing under test is that
## the same contributions compose to three different numbers - and three
## subclasses would let a reader believe it was three different setups.
var speed_policy: AttributeSet.AggregatorPolicy = AttributeSet.AggregatorPolicy.ALL

## What the set did with the damage it was handed, so a test can see that the
## hook ran before the value was cleared.
var absorbed: float = 0.0


func _init() -> void:
	# Fresh instances per set, for the reason TestAttributeSet gives: `@export`
	# defaults are evaluated once and would otherwise be shared.
	speed = AttributeData.new(100.0)
	health = AttributeData.new(100.0)
	damage = AttributeData.new(0.0)
	damage.is_meta = true


func aggregator_policy(attribute_name: StringName) -> AttributeSet.AggregatorPolicy:
	if attribute_name == SPEED:
		return speed_policy
	return AttributeSet.AggregatorPolicy.ALL


## Read the damage that was just written, take it off health, and record it.
##
## What a real set does with a meta attribute. Nothing here clears the value:
## that is the runtime's job and doing it in both places is how one of them
## stops being the one that matters.
func post_gameplay_effect_execute(data: GameplayEffectExecuteData) -> void:
	if data.attribute_name != DAMAGE:
		return
	absorbed = damage.base_value
	health.base_value = health.base_value - absorbed
	health.current_value = health.base_value
