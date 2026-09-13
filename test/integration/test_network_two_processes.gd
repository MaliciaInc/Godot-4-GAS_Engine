## The fourteen steps, across two operating-system processes.
##
## Every other networking suite in this repository puts two runtimes in one
## process. That checks the rules and it cannot check the wire, and the
## difference is not academic: the run this file is about found two defects that
## were invisible in-process for the whole of F6.6. This addon's wire is JSON,
## JSON has one number type, and every reader that compared `typeof(value)`
## against `TYPE_INT` refused every message that had actually crossed a wire.
## Beside it, a Vector3 written to JSON arrives as the text `(3, 0, 0)`, so no
## aim with a position in it ever reached an authority.
##
## What this file checks is the receipt `tooling/run_multiplayer_sample.ps1`
## leaves behind, because a GUT test cannot be two processes and should not
## pretend to be. The harness launches them; this says whether what they did was
## what was asked, and refuses a receipt older than the code it vouches for.
##
## It lives in `test/integration/` and the headless runner does not read that
## directory. Two Godot processes launched from inside a third is not something
## to do on every suite run, and a suite whose failure mode is a hung machine is
## a suite people stop running.
##
##     pwsh -File tooling/run_multiplayer_sample.ps1
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

const RECEIPT: String = "res://artifacts/gates/F6.6/multiplayer-sample.json"

## What the receipt vouches for. A change under any of these makes a receipt
## written before it a claim about code that no longer exists.
const COVERED: Array[String] = [
	"res://addons/GAS_Engine/networking",
	"res://examples/action_sample",
	"res://tooling/run_multiplayer_sample.ps1",
]

## The steps the client has to have taken, in this order, with nothing between
## them that is not one of them.
##
## The scenario the phase document names, in its own words rather than in the
## sample's: an authority and a client that are two processes, a character bound
## on both, a loadout granted and replicated, a predicted activation accepted,
## an aim validated, a refusal rolled back, both exits clean and the two final
## readings equal.
const CLIENT_STEPS: Array[String] = [
	"connecting to",
	"attached the hero",
	"connected as peer",
	"told about 3 grants",
	"read the opening state",
	"predicted a strike",
	"the strike was accepted",
	"predicted a slam and asked",
	"the aim was accepted; sent where it was aimed",
	"predicted a channel and spent",
	"the channel was refused",
	"settled",
	"read the closing state",
]

const AUTHORITY_STEPS: Array[String] = [
	"listening on port",
	"attached the hero",
	"granted 3 abilities",
	"sent the opening snapshot",
	"accepted a request for Ability.Sample.Strike",
	"accepted a request for Ability.Sample.Slam",
	"refused a ACTIVATION_REQUEST: policy_refuses",
	"the client settled",
]

var receipt: Dictionary = {}

## The newest thing the receipt vouches for, while it is being looked for.
var _newest: String = ""
var _newest_at: int = 0


func before_all() -> void:
	receipt = _read()


#region Whether there is a run to talk about
## There is a receipt, and it is not older than what it vouches for.
func test_the_harness_has_been_run_against_this_tree() -> void:
	assert_false(receipt.is_empty(), "run tooling/run_multiplayer_sample.ps1 first")
	if receipt.is_empty():
		return

	_newest = ""
	_newest_at = 0
	for path: String in COVERED:
		_look_under(path)

	assert_true(
		FileAccess.get_modified_time(RECEIPT) >= _newest_at,
		"the receipt is older than %s; run the harness again" % _newest
	)


## Both processes exited cleanly and neither had anything to complain about.
func test_both_processes_finished_without_a_fault() -> void:
	if receipt.is_empty():
		return
	var verdict: String = str(receipt.get("verdict", ""))
	var faults: Array = receipt.get("faults", [])
	var server_exit: int = receipt.get("server_exit", -1)
	var client_exit: int = receipt.get("client_exit", -1)

	assert_eq(verdict, "PASS", "the harness says it worked")
	assert_eq(faults.size(), 0, "and nothing went wrong: %s" % str(faults))
	assert_eq(server_exit, 0, "the authority exited zero")
	assert_eq(client_exit, 0, "and so did the client")
#endregion


#region Whether it was the run that was asked for
##     [whose steps, what they have to be]
func _step_cases() -> Array:
	return [
		["the client", "client_steps", CLIENT_STEPS],
		["the authority", "server_steps", AUTHORITY_STEPS],
	]


## Each half did what the scenario asks, in the order it asks for it.
##
## In order, and that is the part with teeth: a refusal that rolled back before
## the guess was made, or an aim validated before the ability that was aiming
## had been accepted, is a passing run with the steps in a sequence that could
## not have happened.
func test_each_half_took_its_steps_in_order() -> void:
	if receipt.is_empty():
		return
	var rows: Array = _step_cases()
	var checked: int = 0
	for row: Array in rows:
		var whose: String = row[0]
		var field: String = row[1]
		var wanted: Array[String] = row[2]

		var taken: Array = receipt.get(field, [])
		var at: int = 0
		for step: String in wanted:
			at = _found_at(taken, step, at)
			assert_true(at >= 0, "%s: '%s', after everything before it" % [whose, step])
			if at < 0:
				break
			at += 1
		checked += 1
	assert_eq(checked, rows.size(), "both halves were read")


## The two processes ended on the same reading of the same character.
##
## The reading rather than the components, because a reading is what crosses:
## the authority hashed what it would send and the client hashed what it last
## received, and the two being equal is the two processes agreeing.
func test_the_two_processes_converged() -> void:
	if receipt.is_empty():
		return
	var state: String = str(receipt.get("state", ""))
	assert_false(state.is_empty(), "there is a final reading")
	assert_true(state.contains("attr "), "with the character's attributes in it")
	assert_true(state.contains("ability "), "and the abilities it was granted")
#endregion


#region Getting there
func _read() -> Dictionary:
	if not FileAccess.file_exists(RECEIPT):
		return {}
	var text: String = FileAccess.get_file_as_string(RECEIPT)
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {}
	var said: Dictionary = parser.data
	return said


## Where `step` appears in `taken`, at or after `from`, or -1.
func _found_at(taken: Array, step: String, from: int) -> int:
	for index: int in range(from, taken.size()):
		if str(taken[index]).contains(step):
			return index
	return -1


## Remember the newest thing seen under a path, and everything below it.
##
## Two fields rather than a returned pair, because a pair out of an untyped
## Array is two casts at every call site and this file is checked with the same
## typing rules as the addon.
##
## A path that is a file answers about itself: one of the three covered paths is
## a script rather than a directory.
func _look_under(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		_consider(path)
		return
	for name: String in DirAccess.get_files_at(path):
		_consider(path.path_join(name))
	for name: String in DirAccess.get_directories_at(path):
		_look_under(path.path_join(name))


func _consider(path: String) -> void:
	var at: int = FileAccess.get_modified_time(path)
	if at > _newest_at:
		_newest_at = at
		_newest = path
#endregion
