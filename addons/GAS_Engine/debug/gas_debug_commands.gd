## The console half of the runtime debugger: type a line, get an answer.
##
## An overlay is for watching; this is for doing. "Give it to me twenty times
## and tell me what it says" is not a thing anybody clicks through, and every
## project ends up writing the same seven commands against the same seven
## methods - badly, once, in whatever console it already had.
##
## Answers text rather than printing it. A game has its own console, its own
## chat window, its own remote command channel, and one that printed to stdout
## would be usable from exactly none of them.
##
## What it says about an entity is what the overlay draws about it, because they
## are the same pages: a console and a panel that described the same state in
## different words would be two descriptions to keep in step.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name GasDebugCommands extends RefCounted

## What every command starts with, so a host console can route a line here
## without knowing what the commands are.
const PREFIX: String = "gas."

## Each command is the word the thing it is about already goes by, rather than a
## second spelling of it: a switch is named once on GasDebugOptions, and a page
## is named once by itself.
const IGNORE_COSTS: String = PREFIX + String(GasDebugOptions.IGNORE_COSTS)
const IGNORE_COOLDOWNS: String = PREFIX + String(GasDebugOptions.IGNORE_COOLDOWNS)
const LIST: String = PREFIX + "list"
const ACTIVATE: String = PREFIX + "activate"

const ON: String = GasDebugOptions.ON
const OFF: String = GasDebugOptions.OFF

const UNKNOWN_COMMAND: String = "GAS_Engine: no such command '%s'. Try: %s"
const WANTS_ON_OR_OFF: String = "GAS_Engine: '%s' takes on or off, not '%s'."
const WANTS_AN_ENTITY: String = "GAS_Engine: '%s' needs the name of an entity."
const WANTS_AN_ABILITY: String = "GAS_Engine: '%s' needs an entity and an ability."
const NO_SUCH_ENTITY: String = (
	"GAS_Engine: nothing called '%s' has an ability system. Try %s."
)
const NO_SUCH_ABILITY: String = "GAS_Engine: '%s' has no ability called '%s'."
const GRANT_LINE: String = "#%d %s (%s)"
const UNNAMED: String = "unnamed"
const NOTHING_AT_ALL: String = "GAS_Engine: nothing in the scene has an ability system."
const NOTHING_TO_SHOW: String = "GAS_Engine: %s has no %s."
const ACTIVATED: String = "GAS_Engine: %s activated '%s'."
const REFUSED: String = "GAS_Engine: %s refused '%s' - %s (%s)."

const SEPARATOR: String = " | "
const LINE_BREAK: String = "\n"


## The pages a command can print, each answering to its own word.
##
## Built here rather than listed, so a page added to the overlay is a command
## without anybody remembering to add it - and so the console can never offer a
## word that prints nothing.
static func pages() -> Array[GasDebugPage]:
	var offered: Array[GasDebugPage] = [
		GasDebugPageAttributes.new(), GasDebugPageEffects.new(), GasDebugPageTags.new()
	]
	return offered


## Every command there is, for a console offering completion or a bad line
## being told what it could have said.
static func names() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray([
		IGNORE_COSTS, IGNORE_COOLDOWNS, LIST, ACTIVATE
	])
	for page: GasDebugPage in pages():
		found.append(PREFIX + page.command())
	return found


## Run one line and answer what to show.
##
## `within` is any node in the tree being debugged; entities are found from its
## root, so a caller does not have to hold the ability systems itself. That is
## the whole reason a console can be wired into a game in one line.
static func run(line: String, within: Node) -> String:
	var words: PackedStringArray = line.strip_edges().split(" ", false)
	if words.is_empty():
		return UNKNOWN_COMMAND % ["", SEPARATOR.join(names())]

	var command: String = words[0]
	var rest: PackedStringArray = words.slice(1)
	match command:
		IGNORE_COSTS:
			return _switch(command, GasDebugOptions.IGNORE_COSTS, rest)
		IGNORE_COOLDOWNS:
			return _switch(command, GasDebugOptions.IGNORE_COOLDOWNS, rest)
		LIST:
			return _list(within, rest)
		ACTIVATE:
			return _activate(within, rest)

	for page: GasDebugPage in pages():
		if command == PREFIX + page.command():
			return _page(page, within, rest, command)
	return UNKNOWN_COMMAND % [command, SEPARATOR.join(names())]


#region The switches
static func _switch(command: String, switch: StringName, rest: PackedStringArray) -> String:
	var said: String = rest[0] if rest.size() > 0 else ""
	if said != ON and said != OFF:
		return WANTS_ON_OR_OFF % [command, said]
	return GasDebugOptions.set_switch(switch, said == ON)
#endregion


#region Finding an entity
## Every ability system in the tree, by the name of whatever holds it.
##
## By name because that is what a person types. Two nodes with one name is a
## thing a scene is allowed to contain, and the first is answered - which is
## why `gas.list` exists beside this rather than being an afterthought.
static func entities(within: Node) -> Dictionary[String, AbilitySystemComponent]:
	var found: Dictionary[String, AbilitySystemComponent] = {}
	if within == null or not is_instance_valid(within) or within.get_tree() == null:
		return found
	_collect(within.get_tree().root, found)
	return found


static func _collect(
	node: Node, found: Dictionary[String, AbilitySystemComponent]
) -> void:
	var component: AbilitySystemComponent = node as AbilitySystemComponent
	if component != null:
		# Named by its owner where it has one: a person types the character's
		# name, not the name of the component hanging off it.
		var named: String = String(
			component.get_parent().name if component.get_parent() != null else component.name
		)
		if not found.has(named):
			found[named] = component
	for child: Node in node.get_children():
		_collect(child, found)


static func _found(within: Node, named: String) -> AbilitySystemComponent:
	return entities(within).get(named, null)


## Bare, every entity there is. With a name, that entity's grants.
##
## The grants carry their handle as well as their name, because an ability that
## never set `ability_name` has only a handle to be called by - and an entity
## whose abilities cannot be named is an entity `gas.activate` cannot reach.
static func _list(within: Node, rest: PackedStringArray) -> String:
	var known: Dictionary[String, AbilitySystemComponent] = entities(within)
	if known.is_empty():
		return NOTHING_AT_ALL
	if rest.is_empty():
		return LINE_BREAK.join(known.keys())

	var component: AbilitySystemComponent = known.get(rest[0], null)
	if component == null:
		return NO_SUCH_ENTITY % [rest[0], SEPARATOR.join(known.keys())]

	var lines: Array[String] = []
	for ability: GasRuntimeSnapshot.Ability in GasRuntimeSnapshot.of(component).abilities:
		lines.append(GRANT_LINE % [
			ability.handle,
			ability.name if not ability.name.is_empty() else UNNAMED,
			GasDebugPageAbilities.RUNNING if ability.is_running() else GasDebugPageAbilities.READY,
		])
	if lines.is_empty():
		return NOTHING_TO_SHOW % [rest[0], "granted abilities"]
	return LINE_BREAK.join(lines)
#endregion


#region Showing what an entity is
## One page's rows, as lines.
##
## The overlay's own pages, so the console and the panel say the same thing
## about the same entity in the same words.
static func _page(
	page: GasDebugPage, within: Node, rest: PackedStringArray, command: String
) -> String:
	if rest.is_empty():
		return WANTS_AN_ENTITY % command
	var component: AbilitySystemComponent = _found(within, rest[0])
	if component == null:
		return NO_SUCH_ENTITY % [rest[0], SEPARATOR.join(entities(within).keys())]

	var lines: Array[String] = []
	for row: GasDebugPage.Row in page.rows(GasRuntimeSnapshot.of(component)):
		lines.append(row.said())
	if lines.is_empty():
		return NOTHING_TO_SHOW % [rest[0], page.title().to_lower()]
	return LINE_BREAK.join(lines)
#endregion


#region Making something happen
## Activate one ability on one entity, and say what the attempt answered.
##
## The refusal carries its failure tag as well as its status, because the tag is
## what a game's own UI reacts to - and "it did nothing" is the report this
## command exists to replace.
static func _activate(within: Node, rest: PackedStringArray) -> String:
	if rest.size() < 2:
		return WANTS_AN_ABILITY % ACTIVATE
	var component: AbilitySystemComponent = _found(within, rest[0])
	if component == null:
		return NO_SUCH_ENTITY % [rest[0], SEPARATOR.join(entities(within).keys())]

	var spec: GameplayAbilitySpec = _ability_named(component, rest[1])
	if spec == null:
		return NO_SUCH_ABILITY % [rest[0], rest[1]]

	var result: GameplayAbilityActivationResult = component.try_activate_ability_handle(
		spec.handle
	)
	if result.is_ok():
		return ACTIVATED % [rest[0], rest[1]]
	return REFUSED % [
		rest[0],
		rest[1],
		GasDebugMessage.key_of(
			GameplayAbilityActivationResult.Status.keys(), int(result.status)
		),
		String(AbilityFailureTags.of(_error_behind(component, spec))),
	]


## The grant of that name, or of that handle.
##
## Both, because an ability that never set `ability_name` has only a handle to
## be called by, and `gas.list <entity>` prints the handle beside every grant
## for exactly that case.
static func _ability_named(
	component: AbilitySystemComponent, named: String
) -> GameplayAbilitySpec:
	var wanted: String = named.to_lower()
	var by_handle: int = int(named) if named.is_valid_int() else 0
	for spec: GameplayAbilitySpec in component.get_ability_specs():
		if String(spec.definition.ability_name).to_lower() == wanted:
			return spec
		if by_handle != 0 and spec.handle.id == by_handle:
			return spec
	return null


## Why the runtime would refuse this grant, asked of the runtime rather than
## guessed from the status - the two are different vocabularies and only one of
## them has a tag.
static func _error_behind(
	component: AbilitySystemComponent, spec: GameplayAbilitySpec
) -> AbilityRuntime.ActivationError:
	return component.ability_runtime.activation_error(spec)
#endregion
