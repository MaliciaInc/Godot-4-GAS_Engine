## A stand-in for Dialogic's autoload, carrying only its published contract.
##
## One signal, because one signal is all the bridge is allowed to know about.
## If this double ever needs a second member to keep the tests passing, the
## bridge has reached past the surface it promised to depend on - which is
## exactly the thing worth finding out before a point release finds it for us.
##
## Not a copy of Dialogic and not installed as one: the real addon is not in
## this repository, and planting a fake `addons/dialogic` would only prove the
## availability check can be fooled.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name FakeDialogic extends Node

## Dialogic's general-purpose bus. Everything a timeline says goes through here,
## most of it addressed to somebody other than the ability system.
signal signal_event(argument: Variant)


static func build() -> FakeDialogic:
	var fake: FakeDialogic = FakeDialogic.new()
	fake.name = "Dialogic"
	return fake


## Say something on the bus, the way a timeline event does.
##
## A dictionary goes out frozen, because that is what the real addon does:
## DialogicSignalEvent calls `make_read_only()` before emitting. A double
## that handed over a writable copy would let a bridge quietly mutate the
## message and pass every test here, then fail against real Dialogic.
func say(argument: Variant) -> void:
	if argument is Dictionary:
		var frozen: Dictionary = argument
		frozen.make_read_only()
		signal_event.emit(frozen)
		return
	signal_event.emit(argument)
