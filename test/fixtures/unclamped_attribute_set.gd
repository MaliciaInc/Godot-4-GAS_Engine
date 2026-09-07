## An attribute set that lets values go negative, because some games do.
##
## The suite's ordinary set floors every attribute at zero, and that floor was
## hiding a bug rather than preventing it: affordability was decided by
## comparing what a cost asked to write against what the set let through, so on
## a set that clamps, "you cannot afford this" and "the clamp caught it" were
## the same answer. On a set that does not clamp, they are not - the write goes
## through at -10 and the two agree, so the cost reads as affordable and the
## player is charged into debt.
##
## Nothing here is exotic. A game with overdraft, with negative morale, with a
## temperature that goes below zero, authors exactly this set.
##
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name UnclampedAttributeSet extends TestAttributeSet


## Whatever was proposed, durably.
func pre_attribute_base_change(
	_attribute_name: StringName, proposed_base_value: float
) -> float:
	return proposed_base_value


## And whatever was computed, derived.
func pre_attribute_change(
	_attribute_name: StringName, proposed_value: float
) -> float:
	return proposed_value
