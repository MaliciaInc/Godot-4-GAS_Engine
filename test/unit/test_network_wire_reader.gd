## Reading a primitive back off a wire, where the wire is allowed to be wrong.
##
## Everything that crosses is JSON, and JSON has one number type and no opinion
## about what a field was supposed to be. This reader is the one place that asks
## before it converts, so these are the answers it owes: what it makes of a
## whole number written the way JSON writes one, and what it makes of a field
## that is not a number at all.
##
## Driven on the reader rather than through a codec, because a codec's refusal
## can be right for the wrong reason - a message thrown out by the next check
## along looks exactly like a message this one caught.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const A_KEY: String = "some.key"
const MISSING_KEY: String = "nobody.wrote.this"
const FALLBACK: int = -7
const FRACTIONAL_FALLBACK: float = -0.5
const TOLERANCE: float = 0.0001

## Past what a float can hold exactly: 2^53 + 1.
const TOO_BIG_FOR_A_FLOAT: int = 9007199254740993


#region A number
## Both readings of every value, in one table.
##
## One row rather than two tables, because the interesting part is exactly where
## the two answers differ: an integer is a perfectly good fraction, and a
## fraction is not a whole number. Split apart, each half looked like a list of
## things that are not numbers and the asymmetry was in neither of them.
##
##     [what the wire carried, what a whole number reads as, what a fraction does]
const READINGS: Array = [
	["an integer", 5, 5, 5.0],
	["a whole number written the way JSON writes one", 5.0, 5, 5.0],
	["zero", 0, 0, 0.0],
	["a negative", -3, -3, -3.0],
	["a number with a fraction in it", 2.5, FALLBACK, 2.5],
	["text that looks like a number", "5", FALLBACK, FRACTIONAL_FALLBACK],
	["text that does not", "five", FALLBACK, FRACTIONAL_FALLBACK],
	["nothing at all", null, FALLBACK, FRACTIONAL_FALLBACK],
	["a list", [], FALLBACK, FRACTIONAL_FALLBACK],
	["a dictionary", {}, FALLBACK, FRACTIONAL_FALLBACK],
	["a flag", true, FALLBACK, FRACTIONAL_FALLBACK],
]


## `int()` answers 0 for a string, a dictionary and null alike, so a reader
## built on it could not tell "the wire said zero" from "the wire said
## something that is not a number". That is what the fallback is for.
func test_a_number_is_read_only_when_the_wire_carried_one(
	case: Array = use_parameters(READINGS)
) -> void:
	var described: String = case[0]
	var carried: Variant = case[1]
	var whole: int = case[2]
	var fraction: float = case[3]

	assert_eq(
		GameplayWireReader.number_from(carried, FALLBACK), whole, "%s, as a count" % described
	)
	assert_almost_eq(
		GameplayWireReader.fraction_from(carried, FRACTIONAL_FALLBACK),
		fraction,
		TOLERANCE,
		"%s, as a measurement" % described
	)


## A whole number too big for a float comes back as itself.
##
## JSON's one number type is why the reader converts through a float at all, and
## a float cannot hold a whole number past 2^53. A value that arrived as an
## integer never needed that conversion, and doing it anyway would be the reader
## changing something nobody asked it to change.
func test_an_integer_too_big_for_a_float_is_not_rounded_on_the_way_through() -> void:
	assert_eq(
		GameplayWireReader.number_from(TOO_BIG_FOR_A_FLOAT, 0),
		TOO_BIG_FOR_A_FLOAT,
		"the identity is the identity it was"
	)
#endregion


#region Under a key
## A key nobody wrote reads as the fallback, not as zero.
func test_a_key_the_wire_never_carried_reads_as_the_fallback() -> void:
	var said: Dictionary = {}

	assert_eq(GameplayWireReader.number_in(said, MISSING_KEY, FALLBACK), FALLBACK)
	assert_almost_eq(
		GameplayWireReader.fraction_in(said, MISSING_KEY, FRACTIONAL_FALLBACK),
		FRACTIONAL_FALLBACK,
		TOLERANCE
	)


## A key that is there and wrong reads as the fallback too.
##
## The two cases are one answer on purpose: a receiver that treated "absent" and
## "present and unreadable" differently would be a receiver with an opinion
## about which of two machines is broken.
func test_a_key_that_is_there_and_unreadable_reads_as_the_fallback() -> void:
	var said: Dictionary = {A_KEY: "not a number"}

	assert_eq(GameplayWireReader.number_in(said, A_KEY, FALLBACK), FALLBACK)
#endregion


#region A list of tags
## Something that is not a list is not a list of names.
##
## It used to be a crash: the check cast to Array without asking, so a wire that
## carried a string where a tag list belongs walked a null - which is the one
## thing a validator must not do, because validating is what it was called for.
func test_something_that_is_not_a_list_is_not_a_list_of_names() -> void:
	assert_false(GameplayWireReader.tags_are_named("Status.Burning"), "a bare name is not")
	assert_false(GameplayWireReader.tags_are_named({}), "and neither is a dictionary")
	assert_false(GameplayWireReader.tags_are_named(null), "and neither is nothing")


func test_reading_tags_out_of_something_that_is_not_a_list_reads_none() -> void:
	assert_eq(GameplayWireReader.tags_from("Status.Burning").size(), 0, "no tags were read")
	assert_eq(GameplayWireReader.tags_from(null).size(), 0, "and none out of nothing")


## What a real list still does, so the guard above cannot pass by refusing
## everything.
func test_a_list_of_names_still_reads_as_the_names_it_holds() -> void:
	var carried: Array = ["Status.Burning", "Status.Slowed"]

	assert_true(GameplayWireReader.tags_are_named(carried), "it is a list of names")
	assert_eq(GameplayWireReader.tags_from(carried).size(), 2, "and both were read")
#endregion
