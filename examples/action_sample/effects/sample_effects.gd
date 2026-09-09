## The four effects this sample applies, built where a reader can see all of
## them at once.
##
## Built in code rather than authored as `.tres` files so that every number in
## the sample is in the diff and under the same gates as the rest: a person
## reading this can see what a strike costs without opening an inspector. A real
## project would author these in the effect editor F6.4.1 ships, which produces
## exactly these objects.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleEffects extends RefCounted

## What a strike takes off, before anybody's attack stat is involved.
const STRIKE_DAMAGE: float = 12.0

## What the channel drains each time it ticks, and how often it ticks.
const CHANNEL_DRAIN: float = 5.0
const CHANNEL_PERIOD: float = 0.5

## What the slam takes off, and how long its stagger lasts.
const SLAM_DAMAGE: float = 25.0
const STAGGER_SECONDS: float = 3.0

## What a staggered character is, so an ability can refuse to start while it is.
const STAGGERED: StringName = &"Status.Staggered"


## One hit. Instant, so it moves the durable value rather than buffing it.
static func strike() -> GameplayEffect:
	return _instant(_taking(SampleAttributes.HEALTH, STRIKE_DAMAGE))


## The slam's damage, and the stagger it leaves behind.
static func slam() -> GameplayEffect:
	return _instant(_taking(SampleAttributes.HEALTH, SLAM_DAMAGE))


## A stagger: no numbers, one tag, and a clock. What it does is make the
## character something other abilities can ask about.
static func stagger() -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "SampleStagger"
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = STAGGER_SECONDS

	var granting: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	granting.granted_tags = [STAGGERED]
	effect.components.append(granting)
	return effect


## What the channel takes while it runs: mana, a little at a time, for as long
## as the ability is up. Infinite because the ability ends it, not a clock.
static func channel_drain() -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "SampleChannelDrain"
	effect.policy = GameplayEffect.DurationPolicy.INFINITE
	effect.period = CHANNEL_PERIOD
	effect.modifiers = [_taking(SampleAttributes.MANA, CHANNEL_DRAIN)]
	return effect


## The cooldown a strike leaves: a tag and a clock, nothing else.
static func strike_cooldown(seconds: float) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "SampleStrikeCooldown"
	effect.policy = GameplayEffect.DurationPolicy.DURATION
	effect.duration = seconds

	var granting: GameplayEffectTargetTagsComponent = GameplayEffectTargetTagsComponent.new()
	granting.granted_tags = [SampleCues.STRIKE_COOLDOWN]
	effect.components.append(granting)
	return effect


static func _instant(modifier: GameplayEffectModifier) -> GameplayEffect:
	var effect: GameplayEffect = GameplayEffect.new()
	effect.resource_name = "SampleStrike"
	effect.policy = GameplayEffect.DurationPolicy.INSTANT
	effect.modifiers = [modifier]
	return effect


## One modifier that takes `amount` off `attribute`.
##
## Negative, because a cost and a wound are both subtractions and writing the
## minus at each call site is how one of them ends up healing.
static func _taking(attribute: StringName, amount: float) -> GameplayEffectModifier:
	var modifier: GameplayEffectModifier = GameplayEffectModifier.new()
	modifier.attribute_name = attribute
	modifier.operation = GameplayEffectModifier.Operation.ADD

	var scalable: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable.value = -amount
	var magnitude: GameplayScalableMagnitude = GameplayScalableMagnitude.new()
	magnitude.value = scalable
	modifier.magnitude = magnitude
	return modifier
