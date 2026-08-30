## Headless entry point for the GUT suite.
##
## Override 2 routes engine operations through the Godot MCP servers, and none
## of them can pass command-line arguments, so `gut_cmdln.gd -gdir=... -gexit`
## is unreachable. This scene does the same job from inside the project.
##
## The verdict is written to a file rather than only printed. A process that
## quits when the suite ends takes its own stdout with it, so a caller polling
## for output races the exit and reads nothing - which looks exactly like a
## suite that never ran. The file is the receipt `tooling/verify.ps1` reads.
##
## GUT is a vendored dependency pinned byte-identical by step 11.6 and is not
## strictly typed, so every call across its boundary is an unsafe access under
## this project's policy. The suppression below is scoped to exactly that
## boundary. Nothing in `addons/GodotGAS` or in the tests relies on it.
##
## @meta_license: MIT
extends Node

const GUT_RUNNER_SCENE: String = "res://addons/gut/gui/GutRunner.tscn"
const GUT_CONFIG_SCRIPT: String = "res://addons/gut/gut_config.gd"

const TEST_DIRECTORY: String = "res://test/unit"

## Where the verdict is written. The caller copies it into the task receipt.
const RESULT_PATH: String = "res://artifacts/gut/last-run.txt"

## Prefix a caller can grep for in the debug output.
const RESULT_PREFIX: String = "ARHALIES_GUT_RESULT:"

var _runner: Node = null


func _ready() -> void:
	_start_suite()


func _start_suite() -> void:
	var config_script: GDScript = load(GUT_CONFIG_SCRIPT)
	var runner_scene: PackedScene = load(GUT_RUNNER_SCENE)
	if config_script == null or runner_scene == null:
		_report(-1, -1, -1, "GUT is not present at the expected paths")
		return

	@warning_ignore_start("unsafe_method_access", "unsafe_property_access", "unsafe_call_argument")
	var config: RefCounted = config_script.new()
	config.options.dirs = [TEST_DIRECTORY]
	config.options.include_subdirs = true
	config.options.should_exit = false
	config.options.should_maximize = false

	_runner = runner_scene.instantiate()
	add_child(_runner)
	_runner.set_gut_config(config)

	var gut: Object = _runner.get_gut()
	gut.end_run.connect(_on_run_finished)
	_runner.run_tests(false)
	@warning_ignore_restore("unsafe_method_access", "unsafe_property_access", "unsafe_call_argument")


func _on_run_finished() -> void:
	@warning_ignore_start("unsafe_method_access")
	var gut: Object = _runner.get_gut()
	var failures: int = gut.get_fail_count()
	var passes: int = gut.get_pass_count()
	var pending: int = gut.get_pending_count()
	@warning_ignore_restore("unsafe_method_access")

	var collected: int = _collected_script_count()
	var present: int = _test_files_on_disk()
	if collected != present:
		# A script that fails to parse is silently absent from the run, and the
		# suite then reports PASS over tests it never loaded. That happened, and
		# it is exactly the blind-gate failure this phase exists to prevent.
		_report(
			passes,
			maxi(failures, 1),
			pending,
			"COLLECTION MISMATCH: " + str(collected) + " scripts ran but "
			+ str(present) + " exist on disk; the missing ones failed to parse"
		)
		return

	_report(passes, failures, pending, _failing_test_names())


## How many test scripts GUT actually LOADED.
##
## Counting `scripts.size()` is not enough: GUT keeps an entry for a script
## it failed to load, so the count matched while a broken file was silently
## skipped and the suite reported PASS. Verified by breaking a file on
## purpose - the first version of this guard did not notice. `is_loaded` is
## the flag that does.
func _collected_script_count() -> int:
	var loaded: int = 0
	@warning_ignore_start("unsafe_method_access", "unsafe_property_access")
	var gut: Object = _runner.get_gut()
	for script: Object in gut.get_test_collector().scripts:
		if script.is_loaded and not script.tests.is_empty():
			loaded += 1
	@warning_ignore_restore("unsafe_method_access", "unsafe_property_access")
	return loaded


## How many test scripts are on disk, counted independently of GUT.
##
## Two authorities on purpose. Asking GUT how many it found and comparing
## that with itself would answer nothing.
func _test_files_on_disk() -> int:
	var count: int = 0
	for file_name: String in DirAccess.get_files_at(TEST_DIRECTORY):
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			count += 1
	return count


## The tests that did not pass, script by script.
##
## A receipt that says only "13 failed" sends the reader back to the console
## they may no longer have. Naming them is the difference between a receipt
## and a scoreboard.
func _failing_test_names() -> String:
	var names: Array[String] = []
	@warning_ignore_start("unsafe_method_access", "unsafe_property_access")
	var gut: Object = _runner.get_gut()
	for script: Object in gut.get_test_collector().scripts:
		for test: Object in script.tests:
			if test.was_run and not test.is_passing():
				names.append(str(script.get_full_name()) + "::" + str(test.name))
	@warning_ignore_restore("unsafe_method_access", "unsafe_property_access")
	if names.is_empty():
		return "none"
	return (", ").join(names)


func _report(passes: int, failures: int, pending: int, note: String) -> void:
	var verdict: String = "PASS" if failures == 0 and passes > 0 else "FAIL"
	var line: String = (
		RESULT_PREFIX + " " + verdict
		+ " passed=" + str(passes)
		+ " failed=" + str(failures)
		+ " pending=" + str(pending)
	)
	print(line)
	_write_receipt(verdict, line, note)


func _write_receipt(verdict: String, line: String, note: String) -> void:
	DirAccess.make_dir_recursive_absolute(RESULT_PATH.get_base_dir())
	var file: FileAccess = FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("could not write the GUT receipt to " + RESULT_PATH)
		return
	# Stamped so a stale receipt is visible. A previous Godot process holding
	# the session made two runs silently not happen, and the old receipt read
	# as a fresh pass both times.
	file.store_line("RESULT: " + verdict)
	file.store_line("written: " + Time.get_datetime_string_from_system(true))
	file.store_line(line)
	file.store_line("detail: " + note)
	file.close()
