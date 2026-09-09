## The three things every magnitude test needs before it can ask a magnitude
## anything: a flat scalable float, a throwaway spec, and the context to
## resolve against.
##
## Here rather than in each suite because two files test magnitudes now - what
## a magnitude reads, and what it does with what it read - and three builders
## written twice are three places for the two suites to start disagreeing about
## what "a spec" means.
##
## Static: nothing here holds state between calls, and a bench that did would
## be a fixture the suites could leak into each other.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name MagnitudeBench extends RefCounted


## A scalable float that is the same number at every level.
static func flat(value: float) -> GameplayScalableFloat:
	var scalable: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable.value = value
	return scalable


## A throwaway spec for asking a magnitude to resolve() directly, without
## putting an effect through a full application.
static func spec(source: ASCFixture) -> GameplayEffectSpec:
	var effect: GameplayEffect = Factory.instant([] as Array[GameplayEffectModifier])
	var made: GameplayEffectSpec = GameplayEffectSpec.new(
		effect, GameplayEffectContext.new(source.owner)
	)
	made.source_asc = source.asc
	return made


const Factory = preload("res://test/fixtures/test_effect_factory.gd")


## The context that spec resolves in, aimed at a target.
static func context(
	made: GameplayEffectSpec, target_asc: AbilitySystemComponent
) -> GameplayMagnitudeContext:
	return GameplayMagnitudeContext.of(made, made.source_asc, target_asc)


## The curve the magnitude suites bend numbers with.
##
## Two things a Curve does that would otherwise make these assertions about
## the wrong thing. Its domain defaults to 0..1 and it clamps, so a curve
## meant for gameplay numbers has to say what range it covers. And between
## control points it interpolates with tangents rather than in a straight
## line, so the values under test are control points themselves: sampled
## exactly there, the answer is the point, and the test is about where in the
## sequence the curve runs rather than about how it bends.
static func bending_curve() -> Curve:
	var curve: Curve = Curve.new()
	curve.min_domain = 0.0
	curve.max_domain = 1000.0
	curve.min_value = 0.0
	curve.max_value = 2000.0
	curve.add_point(Vector2(0.0, 0.0))
	# 40 and 100 are the two numbers the attribute test could sample - one for
	# each order the curve could run in - and they are far apart here on
	# purpose, so getting the order wrong is not a rounding difference.
	curve.add_point(Vector2(40.0, 0.0))
	curve.add_point(Vector2(50.0, 100.0))
	curve.add_point(Vector2(100.0, 500.0))
	curve.add_point(Vector2(1000.0, 2000.0))
	return curve
