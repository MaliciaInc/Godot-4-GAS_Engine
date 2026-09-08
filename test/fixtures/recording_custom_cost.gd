## A custom cost that writes down what happened to it, and can be told to fail.
##
## The transaction's contract is about order and about what is left behind, and
## neither is visible from outside a real cost - an inventory that lost an item
## looks the same whether it was taken once or taken and put back. So this
## records: prepared, committed and rolled back.
##
## Two things about its shape are forced by how a grant works. The flags are
## `@export`ed because a grant packs the ability into a PackedScene and
## instantiates a fresh copy, and anything not exported comes back as the class
## default - the same trap ChannelingAbility documents. And the ledger is static
## rather than a field, because the copy the engine ends up holding is not the
## object the test configured, so a shared array passed by reference would be
## two arrays by the time anything was written to it.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name RecordingCustomCost extends GameplayAbilityCustomCost

## What every cost in the current test wrote, in the order it happened. Cleared
## by the test rather than by a cost, because a cost does not know when a test
## started.
static var ledger: Array[StringName] = []

## What this cost calls itself in the ledger.
@export var label: StringName = &"cost"

## False refuses at check time, before anything is prepared.
@export var payable: bool = true

## False hands back nothing from prepare(), which refuses the commit while
## nothing has been taken.
@export var preparable: bool = true

## False makes commit() answer false, which is the interesting failure:
## everything before it in the order has already taken something.
@export var commits: bool = true


static func said(what: String, label_of: StringName) -> void:
	ledger.append(StringName(what + ":" + String(label_of)))


static func rollbacks() -> Array[StringName]:
	var undone: Array[StringName] = []
	for entry: StringName in ledger:
		if String(entry).begins_with("rollback:"):
			undone.append(entry)
	return undone


func check(
	_asc: AbilitySystemComponent,
	_spec: GameplayAbilitySpec,
	_level: float
) -> GameplayAbilityCustomCostCheck:
	RecordingCustomCost.said("check", label)
	if payable:
		return GameplayAbilityCustomCostCheck.allowed()
	return GameplayAbilityCustomCostCheck.refused(StringName("Refused." + String(label)))


func prepare(
	_asc: AbilitySystemComponent,
	_spec: GameplayAbilitySpec,
	_level: float
) -> GameplayAbilityPreparedCustomCost:
	RecordingCustomCost.said("prepare", label)
	if not preparable:
		return null
	var prepared: RecordingPreparedCost = RecordingPreparedCost.new()
	prepared.label = label
	prepared.succeeds = commits
	return prepared
