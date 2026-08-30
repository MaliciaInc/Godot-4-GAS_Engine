## GameplayScalableFloat: a number, optionally scaled by level via a curve.
##
## @meta_license: MIT
extends GutTest

const TOLERANCE: float = 0.0001


func test_without_a_curve_the_value_is_returned_unscaled() -> void:
	var scalable: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable.value = 42.0
	assert_almost_eq(scalable.evaluate(1.0), 42.0, TOLERANCE, "no curve, no scaling")
	assert_almost_eq(scalable.evaluate(99.0), 42.0, TOLERANCE, "level does not matter without a curve")


func test_a_curve_multiplies_the_value_by_the_sampled_point() -> void:
	# Godot clamps both axes to [0, 1] by default: max_domain for X, max_value
	# for Y. Without widening both, add_point(Vector2(2.0, 2.0)) silently
	# stores (2.0, 1.0) - the Y value clamped away. Sampling exactly at a
	# control point is then exact for any Bezier curve, tangents included:
	# the curve passes through its own points.
	var curve: Curve = Curve.new()
	curve.max_domain = 2.0
	curve.max_value = 2.0
	curve.add_point(Vector2(1.0, 1.0))
	curve.add_point(Vector2(2.0, 2.0))
	var scalable: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable.value = 10.0
	scalable.scaling_curve = curve

	assert_almost_eq(scalable.evaluate(1.0), 10.0, TOLERANCE, "level 1 samples the first point")
	assert_almost_eq(scalable.evaluate(2.0), 20.0, TOLERANCE, "level 2 samples the second, doubled")


func test_evaluate_does_not_mutate_the_curve() -> void:
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(1.0, 1.0))
	var scalable: GameplayScalableFloat = GameplayScalableFloat.new()
	scalable.value = 5.0
	scalable.scaling_curve = curve

	scalable.evaluate(1.0)
	assert_eq(curve.point_count, 1, "no point was added or removed")
