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
## @meta_license: MIT
class_name FakeDialogic extends Node

## Dialogic's general-purpose bus. Everything a timeline says goes through here,
## most of it addressed to somebody other than the ability system.
signal signal_event(argument: Variant)


static func build() -> FakeDialogic:
	var fake: FakeDialogic = FakeDialogic.new()
	fake.name = "Dialogic"
	return fake


## Say something on the bus, the way a timeline event does.
func say(argument: Variant) -> void:
	signal_event.emit(argument)
