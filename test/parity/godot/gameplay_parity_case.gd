## One contract taken from the reference, written down so a machine can check it.
##
## A case is not a test. It is a statement about what the reference engine does,
## with the version it was taken from stamped on it, and it is deliberately
## data: the same eleven fields for every case, so nothing can be checked in one
## case and quietly skipped in the next.
##
## The eleven are the ones the phase names, and each of them is here because
## leaving it out lets a case pass while being wrong in that dimension. A case
## that only asserted attributes would be satisfied by an engine that produced
## the right numbers by firing the wrong signals in the wrong order and handing
## out a different handle each time.
##
## No Unreal process is run. The expectations are authored from the reference's
## documented behaviour and stamped with the version they were taken from, which
## is what makes them reviewable: a wrong expectation is a wrong sentence in a
## file rather than an invisible disagreement with a binary nobody has.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name GameplayParityCase extends RefCounted

## Which reference this case was taken from. Stamped per case rather than per
## corpus: a case revised against a later reference has to say so, and a corpus
## with one version at the top would hide that.
const REFERENCE: String = "Unreal Engine 5.7.4, CL 51494982"

var id: StringName = &""
var reference_version: String = REFERENCE

#region The initial state
## What the character is before anything happens.
var attributes: Dictionary[StringName, float] = {}
var tags: Array[StringName] = []
#endregion

#region The input
## What is done to it. Takes the fixture and does one thing.
##
## A Callable rather than a description of an action, because the alternative is
## a second little language for saying "apply this effect" - and a language with
## one user is a language nobody checks.
var input: Callable = Callable()
#endregion

#region What the reference says happens
## Attribute current values afterwards, by name.
var expected_attributes: Dictionary[StringName, float] = {}

## Tags held afterwards, by reference count.
var expected_tags: Dictionary[StringName, int] = {}

## How many effects are running afterwards.
var expected_effects: int = 0

## Which signals fired, in any order. A set, because most of the time what
## matters is that the announcement happened at all.
var expected_signals: Array[StringName] = []

## And the ones whose order is part of the contract, as a subsequence: these
## must appear, in this order, among everything that fired. Separate from the
## set above because most orderings are not contracts and pinning all of them
## would make every case brittle to an unrelated change.
var expected_order: Array[StringName] = []

## A named rule about handles and identity, checked by the runner.
## See GameplayParityRunner.IDENTITY_RULES.
var expected_identity: StringName = &""

## A named rule about what a person can author, checked the same way.
## See GameplayParityRunner.AUTHORING_RULES.
var expected_authoring: StringName = &""
#endregion


## Whether this case says all eleven things.
##
## Checked before it is run, so a case that forgot half of itself is reported as
## an incomplete case rather than as a passing one.
func is_complete() -> bool:
	return (
		id != &""
		and not reference_version.is_empty()
		and input.is_valid()
		and not attributes.is_empty()
		and not expected_attributes.is_empty()
		and expected_identity != &""
		and expected_authoring != &""
	)
