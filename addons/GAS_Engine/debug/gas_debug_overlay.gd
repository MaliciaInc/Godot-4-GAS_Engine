## The runtime debugger, in the running game rather than in the editor.
##
## The editor's debugger needs the editor: it is an EditorPlugin reading
## messages over the remote-debug channel, and it is not there in a build
## somebody exported to look at on a console, on a phone, or on the machine of
## whoever reported the bug. This is the same information, drawn by the game
## itself.
##
## Instantiated by the game, not an autoload. A debugging surface that installed
## itself into every project would be one more thing in the tree of every game
## that ships this addon, and the games that want it want it on a key of their
## choosing.
##
## Draws nothing it decided: every line comes from a GasDebugPage, which turns
## one snapshot into rows without touching a Control, and GasDebugTable puts the
## rows and the tabs on screen the way the editor's Debugger tab does. What is
## here is the heading, the watching and the clock.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
class_name GasDebugOverlay extends CanvasLayer

## The scene a game instantiates. Named here so a game says
## `GasDebugOverlay.SCENE` rather than spelling a path that moves.
const SCENE: String = "res://addons/GAS_Engine/debug/gas_debug_overlay.tscn"

## How often the table is rebuilt while something is being watched.
##
## Four times a second: fast enough that a cooldown visibly counts down, slow
## enough that reading it is not itself the load somebody is measuring.
const DEFAULT_INTERVAL: float = 0.25

## What the heading says when nothing is being watched.
const NOBODY: String = "GAS_Engine — nothing watched"
const WATCHING: String = "GAS_Engine — %s"

@export var seconds_between_refreshes: float = DEFAULT_INTERVAL

## How a row worth looking at is drawn, and how the rest are.
##
## Exported rather than fixed, and named engine colours rather than channels
## somebody picked: this is drawn over somebody else's game, and the two
## colours that read as "look here" and "ordinary" against their art are theirs
## to choose. The editor's own theme is not reachable from here and should not
## be - a running game must name nothing under `editor/`.
@export var notable_color: Color = Color.ORANGE
@export var ordinary_color: Color = Color.LIGHT_GRAY

## How many attribute changes are kept for the entity being watched.
@export var history_limit: int = GasAttributeHistory.DEFAULT_LIMIT

## Godot's own size, which is what the overlay draws at unless told otherwise.
const DEFAULT_FONT_SIZE: int = 16

## The types whose text the overlay sizes.
const DRAWN_TYPES: Array[StringName] = [
	GASThemeNames.LABEL_TYPE, GASThemeNames.BUTTON_TYPE, GASThemeNames.TREE_TYPE
]

## How big the overlay's text is, whatever the game's theme says.
##
## Said by the overlay rather than left to the tree it stands in. A Control that
## names no size takes the one from the theme around it, and a game whose theme
## said 96 drew this heading and table at 96: a panel anchored to half a 1920 by
## 1080 screen needed 1193 by 1408, and showed eight rows. It looked right in the
## editor, whose theme is quiet. A game that wants it bigger says so here.
@export var font_size: int = DEFAULT_FONT_SIZE

var _watched: AbilitySystemComponent = null
var _history: GasAttributeHistory = GasAttributeHistory.new()
var _pages: Array[GasDebugPage] = []
var _showing: int = 0
var _since_last_refresh: float = 0.0

@onready var _tabs: HBoxContainer = $Panel/Body/Tabs
@onready var _heading: Label = $Panel/Body/Heading
@onready var _table: Tree = $Panel/Body/Table


#region Lifecycle
func _ready() -> void:
	_pages = GasDebugCommands.pages()
	_history.limit = history_limit
	($Panel as Control).theme = _own_theme()
	GasDebugTable.build_tabs(_tabs, _pages, show_page)
	refresh()


## A theme that names the size of every piece of text the overlay draws.
##
## Each type named outright rather than only a default size: the lookup walks the
## chain by type, so a game theme naming Label beats a default set nearer the
## label. Built here rather than borrowed from the Composer's, because a running
## game must name nothing under `editor/`.
func _own_theme() -> Theme:
	var own: Theme = Theme.new()
	own.default_font_size = font_size
	for kind: StringName in DRAWN_TYPES:
		own.set_font_size(GASThemeNames.FONT_SIZE, kind, font_size)
	own.set_font_size(GASThemeNames.TITLE_BUTTON_FONT_SIZE, GASThemeNames.TREE_TYPE, font_size)
	return own


## Keep drawing while the game is paused.
##
## Half of what somebody uses this for is looking at a frozen fight, and an
## overlay that stopped updating with the game would be one they have to
## unpause to read.
func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _watched == null:
		return
	_since_last_refresh += delta
	if _since_last_refresh < seconds_between_refreshes:
		return
	_since_last_refresh = 0.0
	refresh()


func _exit_tree() -> void:
	_history.stop()
#endregion


#region What is being watched
## Start showing this entity, and start remembering what happens to it.
##
## Answers whether it attached, so a caller can tell a component it passed by
## mistake from one that is simply quiet.
func watch(component: AbilitySystemComponent) -> bool:
	if component == null or not is_instance_valid(component):
		return false
	_history.stop()
	_history.forget()
	_history.limit = history_limit
	_history.watch(component)
	_watched = component
	refresh()
	return true


## Stop watching, and forget what was recorded.
func stop() -> void:
	_history.stop()
	_history.forget()
	_watched = null
	refresh()


func watched() -> AbilitySystemComponent:
	return _watched


## What the entity looks like right now.
##
## Taken fresh rather than kept, so a caller asking twice gets two answers
## rather than one that was true when the table was last drawn.
func snapshot() -> GasRuntimeSnapshot:
	return GasRuntimeSnapshot.of(_watched, _history)


## The pages, in the order they are tabbed.
func pages() -> Array[GasDebugPage]:
	return _pages


## Which page is on screen.
func showing() -> int:
	return _showing


## Show one page, by its position in `pages()`.
##
## Out of range is ignored rather than clamped: a caller asking for a page that
## is not there has a bug, and quietly showing them a different one is how it
## stays hidden.
func show_page(index: int) -> bool:
	if index < 0 or index >= _pages.size():
		return false
	_showing = index
	refresh()
	return true


## The history being kept, so a game can read it or clear it.
func history() -> GasAttributeHistory:
	return _history
#endregion


#region Drawing
## Rebuild the table from a fresh snapshot.
func refresh() -> void:
	if not is_inside_tree() or _table == null:
		return
	var taken: GasRuntimeSnapshot = snapshot()
	_heading.text = NOBODY if _watched == null else WATCHING % GasDebugTable.named(taken)
	var page: GasDebugPage = _pages[_showing] if _showing < _pages.size() else null
	GasDebugTable.draw(_table, page, taken, notable_color, ordinary_color)
#endregion
