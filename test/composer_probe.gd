## Can the Ability Composer open this game's abilities?
##
## The strongest thing the framework claims is that it never learns anything
## about a particular game. This is the other half of that claim: a tool built
## against the engine's own reference abilities, pointed at abilities somebody
## wrote for a real game without ever thinking about the Composer.
##
## Nothing here is a pass or a fail on its own. A file the Composer opens
## read-only is not a broken file - it is the tool saying which construction it
## cannot draw, which is exactly what it is supposed to say.
##
## @meta_license: MIT
extends Node

const ABILITIES: Array[String] = [
	"res://src/combat/abilities/battler_ability.gd",
	"res://src/combat/abilities/damage_ability.gd",
	"res://src/combat/abilities/empower_ability.gd",
	"res://src/combat/abilities/heal_ability.gd",
	"res://src/combat/abilities/melee_attack_ability.gd",
	"res://src/combat/abilities/ranged_attack_ability.gd",
]


func _ready() -> void:
	print("\n===== COMPOSER vs THIS GAME =====")
	for path: String in ABILITIES:
		_read(path)
	print("=================================")
	get_tree().quit(0)


func _read(path: String) -> void:
	var source: String = FileAccess.get_file_as_string(path)
	var graph: ComposerGraph = ComposerReader.read(source, path)

	if not graph.is_editable():
		print("[composer] %-28s READ-ONLY  %s" % [path.get_file(), graph.blocked_reason()])
		return

	var printed: ComposerWriter.Result = ComposerWriter.apply(graph, source)
	var same: bool = printed.is_ok() and printed.text == source
	print("[composer] %-28s %d nodes, %d wires, %d notes, round-trip=%s" % [
		path.get_file(), graph.nodes.size(), graph.connections.size(),
		graph.diagnostics.size(), "byte for byte" if same else "CHANGED THE FILE"
	])
	for found: ComposerGraph.Diagnostic in graph.diagnostics:
		print("             line %d: %s" % [found.span.first_line, found.message])
