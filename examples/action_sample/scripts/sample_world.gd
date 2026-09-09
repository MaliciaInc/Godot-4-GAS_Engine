## Everything this sample is, in one node.
##
## A hero, three things to hit, the cues bound, and the runtime overlay watching
## the hero. It is the root of `main.tscn` and it is also what the probe builds,
## so what a person sees when they press play is what the automated check ran
## against - a sample whose demo and whose test are two different scenes is a
## sample that passes its test and looks wrong.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleWorld extends Node3D

## How many things there are to hit, and how far apart.
const DUMMIES: int = 3
const SPACING: float = 3.0

var hero: SampleHero = null
var dummies: Array[SampleHero] = []

## The debugger the game draws itself, watching the hero.
var overlay: GasDebugOverlay = null

## How many of this sample's cues were bound into the running manager. Zero
## means the addon's autoload is not there, which is worth telling somebody.
var bound_cues: int = 0


func _ready() -> void:
	build()


## Put the sample together.
##
## Called from `_ready()` when the scene is played, and directly by the probe,
## which cannot wait for frames and should not have to.
func build() -> void:
	if hero != null:
		return
	bound_cues = SampleCues.bind_into(SampleCues.manager_from(self))

	hero = _character("Hero", Vector3.ZERO)
	for index: int in DUMMIES:
		dummies.append(_character("Dummy%d" % index, Vector3.RIGHT * SPACING * (index + 1)))

	overlay = _overlay()
	if overlay != null:
		overlay.watch(hero.asc)


## Take the sample's cues back out of the manager it shares with everything
## else, so a project that unloads the sample is not left with them bound.
func _exit_tree() -> void:
	SampleCues.unbind_from(SampleCues.manager_from(self))


## Run one console line against this world.
##
## The door a game's own console calls. Everything the seven commands can say
## about this sample goes through here, so a project wiring a console up has one
## call to make rather than seven.
func console(line: String) -> String:
	return GasDebugCommands.run(line, self)


func _character(named: String, at: Vector3) -> SampleHero:
	var made: SampleHero = SampleHero.new()
	made.name = named
	made.position = at
	add_child(made)
	made.equip()
	return made


## The overlay, instantiated from the scene the addon ships.
##
## Null when the addon is not installed, which is a thing to survive rather than
## to crash on: the sample is the first thing somebody opens.
func _overlay() -> GasDebugOverlay:
	var scene: PackedScene = load(GasDebugOverlay.SCENE)
	if scene == null:
		return null
	var made: GasDebugOverlay = scene.instantiate()
	add_child(made)
	return made
