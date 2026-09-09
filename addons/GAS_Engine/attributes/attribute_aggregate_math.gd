## The two ways this engine folds contributions into a value.
##
## They are genuinely different arithmetic, not a setting on one formula, which
## is why both are written out. Two +50% buffs are worth 2.25x under the
## Godot-native rules and 2.0x under Unreal's, and neither is a bug: one
## multiplies the products, the other adds the bonuses and multiplies once.
## A game that ships with the first and is told the second is "the fix" has had
## every stat in it silently rebalanced.
##
## Unreal's also folds in passes. Each channel composes over what the last one
## produced, which is what lets a game say "this multiplies the buffed value,
## not the base" without every effect having to know about every other.
##
## Pure: it is handed a base and a list, and it returns a number or a reason it
## could not. Nothing here reads the world, so a fold can be run against
## candidate contributions before any of them are published.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name AttributeAggregateMath extends RefCounted

## The most channels a modifier may declare, and therefore how many passes a
## fold makes. Ten, matching the modifier's own exported range.
const CHANNELS: int = 10


## What a fold produced, or why it could not.
class Composed extends RefCounted:
	var value: float = 0.0
	var status: AttributeEvaluationResult.Status = AttributeEvaluationResult.Status.OK

	## Which override decided the value, when one did. Carried out so a caller
	## can say which modifier won rather than only what it won with.
	var winning_override_application_order: int = -1
	var winning_override_modifier_index: int = -1

	func is_ok() -> bool:
		return status == AttributeEvaluationResult.Status.OK

	static func failed(why: AttributeEvaluationResult.Status) -> Composed:
		var made: Composed = Composed.new()
		made.status = why
		return made


## What one modifier of a stack is worth, by what its operation means.
##
## A stack of two is not "twice the magnitude" for every arm. Doubling an
## additive bonus is right; doubling a multiplier turns +50% into +200% rather
## than +100%; and doubling an override is meaningless, because an override is a
## value rather than an amount and two of them are still that value.
static func stack_scaled(
	magnitude: float,
	stacks: float,
	operation: GameplayEffectModifier.Operation,
	unreal: bool = false
) -> float:
	# Under the Unreal profile the legacy names are the additive arms, in the
	# fold and therefore here as well. A stack has to scale the arm its
	# magnitude will be folded into, or the two disagree the first time a
	# stacking effect is authored with the legacy spelling.
	var arm: GameplayEffectModifier.Operation = operation
	if unreal:
		if operation == GameplayEffectModifier.Operation.MULTIPLY:
			arm = GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE
		elif operation == GameplayEffectModifier.Operation.DIVIDE:
			arm = GameplayEffectModifier.Operation.DIVIDE_ADDITIVE
	match arm:
		GameplayEffectModifier.Operation.OVERRIDE:
			return magnitude
		GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE, \
		GameplayEffectModifier.Operation.DIVIDE_ADDITIVE:
			# The bias stacks, not the factor: two stacks of x1.5 are +100%.
			return 1.0 + (magnitude - 1.0) * stacks
		GameplayEffectModifier.Operation.MULTIPLY_COMPOUND:
			# Compound means applied once per stack.
			return pow(magnitude, stacks)
	return magnitude * stacks


#region Godot-native
## One pass, products multiplied, and the last override applied wins.
##
## What this engine has always done, kept exactly. Every project already built
## on it composes to the same numbers it did before there was a second way.
static func godot_native(
	base: float, attribute_name: StringName, contributions: Array[AttributeModifierContribution]
) -> Composed:
	var made: Composed = Composed.new()
	var total_add: float = 0.0
	var product_multiply: float = 1.0
	var product_divide: float = 1.0
	var winner: AttributeModifierContribution = null

	for contribution: AttributeModifierContribution in contributions:
		if contribution.attribute_name != attribute_name:
			continue
		match contribution.operation:
			GameplayEffectModifier.Operation.ADD:
				total_add += contribution.magnitude
			GameplayEffectModifier.Operation.MULTIPLY:
				product_multiply *= contribution.magnitude
			GameplayEffectModifier.Operation.DIVIDE:
				# A zero divisor is an invalid configuration, never a no-op.
				# Ignoring it silently is how a designer ships a stat that is
				# quietly wrong instead of loudly broken.
				if is_zero_approx(contribution.magnitude):
					return Composed.failed(AttributeEvaluationResult.Status.DIVISION_BY_ZERO)
				product_divide *= contribution.magnitude
			GameplayEffectModifier.Operation.OVERRIDE:
				if _last_applied_beats(contribution, winner):
					winner = contribution
			_:
				# The UE-only operations have no meaning in this arithmetic.
				# Refused rather than approximated: an effect authored for one
				# profile and composed under the other must say so.
				return Composed.failed(AttributeEvaluationResult.Status.INVALID_OPERATION)

	made.value = ((base + total_add) * product_multiply) / product_divide
	if winner != null:
		made.value = winner.magnitude
		made.winning_override_application_order = winner.application_order
		made.winning_override_modifier_index = winner.modifier_index
	return _finite(made)


## Last applied override wins: later application first, then higher modifier
## index within the same application. Both axes are compared, so two overrides
## from one effect are never resolved by array order.
static func _last_applied_beats(
	candidate: AttributeModifierContribution, winner: AttributeModifierContribution
) -> bool:
	if winner == null:
		return true
	if candidate.application_order != winner.application_order:
		return candidate.application_order > winner.application_order
	return candidate.modifier_index > winner.modifier_index
#endregion


#region Unreal
## One pass per channel, each over what the last one produced.
##
##     ((value + AddBase) * MultiplyAdditive / DivideAdditive)
##         * MultiplyCompound + AddFinal
##
## where the additive multipliers are `1 + sum(magnitude - 1)` - so two +50%
## bonuses are +100%, not +125% - and the compound one is the plain product.
##
## The legacy MULTIPLY and DIVIDE keep their meaning here rather than being
## refused: they are products, so they fold in with the compound ones. Dropping
## them would silently delete an authored effect from the aggregate.
##
## `through_channel` stops the pass early, which is what a magnitude asking
## what an attribute would be before the last channels ran needs. A ceiling
## rather than a second function: the arithmetic is the same arithmetic, and
## a copy of it that stopped sooner would be a second answer to drift from.
static func unreal(
	base: float,
	attribute_name: StringName,
	contributions: Array[AttributeModifierContribution],
	through_channel: int = CHANNELS - 1
) -> Composed:
	var made: Composed = Composed.new()
	made.value = base

	for channel: int in mini(through_channel + 1, CHANNELS):
		var folded: Composed = _one_channel(made.value, attribute_name, contributions, channel)
		if not folded.is_ok():
			return folded
		made.value = folded.value
		if folded.winning_override_modifier_index >= 0:
			made.winning_override_application_order = folded.winning_override_application_order
			made.winning_override_modifier_index = folded.winning_override_modifier_index

	return _finite(made)


static func _one_channel(
	value: float,
	attribute_name: StringName,
	contributions: Array[AttributeModifierContribution],
	channel: int
) -> Composed:
	var made: Composed = Composed.new()
	var add_base: float = 0.0
	var add_final: float = 0.0
	var multiply_additive: float = 1.0
	var divide_additive: float = 1.0
	var multiply_compound: float = 1.0
	var divide_compound: float = 1.0
	var winner: AttributeModifierContribution = null

	for contribution: AttributeModifierContribution in contributions:
		if (
			contribution.attribute_name != attribute_name
			or contribution.evaluation_channel != channel
		):
			continue
		match contribution.operation:
			GameplayEffectModifier.Operation.ADD:
				add_base += contribution.magnitude
			GameplayEffectModifier.Operation.ADD_FINAL:
				add_final += contribution.magnitude
			GameplayEffectModifier.Operation.MULTIPLY_ADDITIVE:
				multiply_additive += contribution.magnitude - 1.0
			GameplayEffectModifier.Operation.DIVIDE_ADDITIVE:
				divide_additive += contribution.magnitude - 1.0
			GameplayEffectModifier.Operation.MULTIPLY_COMPOUND:
				multiply_compound *= contribution.magnitude
			# Unreal's own legacy spellings. `Multiplicitive` and `Division` are
			# aliases of the additive arms there rather than compounding ones, so
			# a modifier authored as MULTIPLY under this profile has to fold the
			# way the reference folds a modifier by that name. Otherwise two x1.5
			# are 2.25 here and 2.0 in the engine this profile exists to agree
			# with, under an operation spelled the same in both.
			GameplayEffectModifier.Operation.MULTIPLY:
				multiply_additive += contribution.magnitude - 1.0
			GameplayEffectModifier.Operation.DIVIDE:
				if is_zero_approx(contribution.magnitude):
					return Composed.failed(AttributeEvaluationResult.Status.DIVISION_BY_ZERO)
				divide_additive += contribution.magnitude - 1.0
			GameplayEffectModifier.Operation.OVERRIDE:
				if _first_eligible_beats(contribution, winner):
					winner = contribution
			_:
				return Composed.failed(AttributeEvaluationResult.Status.INVALID_OPERATION)

	if is_zero_approx(divide_additive) or is_zero_approx(divide_compound):
		return Composed.failed(AttributeEvaluationResult.Status.DIVISION_BY_ZERO)

	made.value = (
		((value + add_base) * multiply_additive / divide_additive)
		* multiply_compound / divide_compound
		+ add_final
	)

	if winner != null:
		made.value = winner.magnitude
		made.winning_override_application_order = winner.application_order
		made.winning_override_modifier_index = winner.modifier_index
	return made


## First eligible override wins, by the channel's own evaluation order: earlier
## application first, then lower modifier index. The opposite of the
## Godot-native rule, deliberately - in Unreal an override claims the attribute
## and later ones do not take it back.
static func _first_eligible_beats(
	candidate: AttributeModifierContribution, winner: AttributeModifierContribution
) -> bool:
	if winner == null:
		return true
	if candidate.application_order != winner.application_order:
		return candidate.application_order < winner.application_order
	return candidate.modifier_index < winner.modifier_index
#endregion


static func _finite(made: Composed) -> Composed:
	if not is_finite(made.value):
		return Composed.failed(AttributeEvaluationResult.Status.NON_FINITE_VALUE)
	return made
