## Reading the plugin's source, because the plugin cannot be built.
##
## `EditorPlugin` refuses to be instantiated outside the editor - "can only be
## instantiated by editor" - so nothing headless can call `_enter_tree()` and
## watch what it wires. What is left is the source, and what a suite can assert
## about it is that the lines which do the wiring are there.
##
## Weaker than driving it, and honest about being weaker: it catches a menu item
## added and never taken back, a handler renamed out from under its connection,
## a creator that stopped being called - which are the ways this wiring has
## actually broken. It cannot catch wiring that is present and wrong.
##
## No `class_name`: the suites reach this through `preload`, for the reason
## `cue_probe.gd` gives - a global name resolves only once Godot has built its
## class cache, and this project has to parse on a checkout that never had one.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends RefCounted

const PLUGIN_SOURCE: String = "res://addons/GAS_Engine/gas_engine_plugin.gd"


## Which of these lines the plugin's source does not contain, described.
##
## `wired` is a table of [what the line does, the line]. Empty means every one
## of them is there, which is the only answer a caller should accept.
static func missing(wired: Array) -> Array[String]:
	var source: String = FileAccess.get_file_as_string(PLUGIN_SOURCE)
	if source.is_empty():
		return ["the plugin's source could not be read at all"]

	var absent: Array[String] = []
	for row: Array in wired:
		var described: String = row[0]
		var needle: String = row[1]
		if not source.contains(needle):
			absent.append("%s: %s" % [described, needle])
	return absent
