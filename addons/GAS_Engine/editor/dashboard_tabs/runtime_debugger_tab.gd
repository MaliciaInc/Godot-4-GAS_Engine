## GAS_Engine scene-state inspector for the currently edited scene.
##
## A reader, never a second gameplay runtime - everything shown here comes
## from GasRuntimeSnapshot, which itself only reads public runtime APIs.
## Nothing on this tab writes back into gameplay state.
##
## Builds its own children in code rather than a pre-authored .tscn subtree:
## there is nothing here a designer edits, so there is nothing worth an
## inspector-authored layout for.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0

@tool
@icon("res://addons/GAS_Engine/icons/gas_engine_asc.svg")
extends Control

## How often the tree refreshes while visible and an ASC is selected -
## fast enough to feel live, slow enough not to fight the editor for frames.
const REFRESH_INTERVAL_SECONDS: float = 0.5

## Shown for an ASC that exists in the edited scene but has never started.
##
## An AbilitySystemComponent builds every runtime it owns in `_ready`, and
## the editor does not run `_ready` for a node in a scene being edited - the
## component is not a `@tool` script, and making it one would run the whole
## gameplay engine at design time and rewrite the designer's exported
## attribute sets on the way past.
##
## So every section below is empty, and used to be empty in silence: seven
## headings all reading (0), which is indistinguishable from an engine that
## is not working. Saying it is the difference between that and "nothing has
## happened yet".
const NOT_STARTED: String = (
	"%s exists in the edited scene but has not started: an AbilitySystemComponent builds its runtime in _ready, which the editor does not run. There is no runtime state to read until the scene is played."
)

var _asc_picker: OptionButton = null
var _refresh_button: Button = null
var _tree: Tree = null
var _status_label: Label = null

var _known_ascs: Array[AbilitySystemComponent] = []

## What the last scan found, so a refresh can put it back after replacing it
## with something more specific about the selected component.
var _scan_status: String = ""
var _time_since_refresh: float = REFRESH_INTERVAL_SECONDS


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_build_ui()
	_rescan_ascs()
	set_process(true)


func _process(delta: float) -> void:
	if not visible or not Engine.is_editor_hint():
		return
	_time_since_refresh += delta
	if _time_since_refresh < REFRESH_INTERVAL_SECONDS:
		return
	_time_since_refresh = 0.0
	_refresh()


#region UI construction
func _build_ui() -> void:
	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_box)

	var header: HBoxContainer = HBoxContainer.new()
	root_box.add_child(header)

	_asc_picker = OptionButton.new()
	_asc_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asc_picker.item_selected.connect(func(_index: int) -> void: _refresh())
	header.add_child(_asc_picker)

	var rescan_button: Button = Button.new()
	rescan_button.text = "Rescan"
	rescan_button.tooltip_text = "Find every AbilitySystemComponent in the edited scene"
	rescan_button.pressed.connect(_rescan_ascs)
	header.add_child(rescan_button)

	_refresh_button = Button.new()
	_refresh_button.text = "Refresh"
	_refresh_button.pressed.connect(_refresh)
	header.add_child(_refresh_button)

	_status_label = Label.new()
	root_box.add_child(_status_label)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = 2
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Name")
	_tree.set_column_title(1, "Value")
	root_box.add_child(_tree)
#endregion


#region ASC discovery
func _rescan_ascs() -> void:
	_known_ascs.clear()
	_asc_picker.clear()
	var scene_root: Node = EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null
	if scene_root != null:
		_collect_ascs(scene_root)
	for asc: AbilitySystemComponent in _known_ascs:
		_asc_picker.add_item(String(asc.get_path()))
	_scan_status = (
		"%d AbilitySystemComponent(s) found in the edited scene" % _known_ascs.size()
		if not _known_ascs.is_empty()
		else "No AbilitySystemComponent found in the edited scene - open one that has one, then Rescan"
	)
	_status_label.text = _scan_status
	_refresh()


func _collect_ascs(node: Node) -> void:
	var asc: AbilitySystemComponent = node as AbilitySystemComponent
	if asc != null:
		_known_ascs.append(asc)
	for child: Node in node.get_children():
		_collect_ascs(child)


func _selected_asc() -> AbilitySystemComponent:
	var index: int = _asc_picker.selected
	if index < 0 or index >= _known_ascs.size():
		return null
	var asc: AbilitySystemComponent = _known_ascs[index]
	return asc if is_instance_valid(asc) else null
#endregion


#region Refresh
func _refresh() -> void:
	if _tree == null:
		return
	_tree.clear()
	var asc: AbilitySystemComponent = _selected_asc()
	if asc == null:
		return

	# `_wire_runtimes()` is the first thing `_ready` does, so an unset
	# back-reference is exactly "this component has never started" - asked of
	# the runtime itself rather than guessed at from an empty snapshot, which
	# a started-but-idle component would also produce.
	if asc.effects.owner_asc == null:
		_status_label.text = NOT_STARTED % String(asc.get_path())
		return

	_status_label.text = _scan_status
	var snapshot: GasRuntimeSnapshot = GasRuntimeSnapshot.capture(asc)
	var root: TreeItem = _tree.create_item()
	_build_attributes(root, snapshot.attributes)
	_build_tags(root, snapshot.tags)
	_build_effects(root, snapshot.effects)
	_build_abilities(root, snapshot.abilities)
	_build_tasks(root, snapshot.tasks)
	_build_cues(root, snapshot.cues)
	_build_refusals(root, snapshot.recent_refusals)


func _section(root: TreeItem, title: String, count: int) -> TreeItem:
	var section: TreeItem = _tree.create_item(root)
	section.set_text(0, "%s (%d)" % [title, count])
	return section


func _row(parent: TreeItem, name: String, value: String) -> TreeItem:
	var item: TreeItem = _tree.create_item(parent)
	item.set_text(0, name)
	item.set_text(1, value)
	return item


func _build_attributes(root: TreeItem, attributes: Array[GasAttributeSnapshot]) -> void:
	var section: TreeItem = _section(root, "Attribute Breakdown", attributes.size())
	for attribute: GasAttributeSnapshot in attributes:
		var row: TreeItem = _row(
			section, String(attribute.attribute_name),
			"base=%s current=%s" % [attribute.base_value, attribute.current_value]
		)
		for contribution: GasAttributeSnapshot.Contribution in attribute.contributions:
			var operation_name: String = GameplayEffectModifier.Operation.keys()[contribution.operation]
			_row(
				row, "contribution",
				"effect=%s op=%s magnitude=%s order=%d stack_factor=%d" % [
					_handle_text(contribution.effect_handle), operation_name,
					contribution.magnitude, contribution.application_order, contribution.stack_factor
				]
			)


func _build_tags(root: TreeItem, tags: Array[GasTagSnapshot]) -> void:
	var section: TreeItem = _section(root, "Tags", tags.size())
	for tag: GasTagSnapshot in tags:
		_row(
			section, String(tag.tag),
			"count=%d activation_owned=%s granting=%d" % [
				tag.count, tag.is_activation_owned, tag.granting_effect_handles.size()
			]
		)


func _build_effects(root: TreeItem, effects: Array[GasEffectSnapshot]) -> void:
	var section: TreeItem = _section(root, "Active Effects", effects.size())
	for effect: GasEffectSnapshot in effects:
		var effect_name: String = effect.definition.resource_path.get_file() if effect.definition != null else "?"
		_row(
			section, effect_name,
			"handle=%s inhibited=%s stacks=%d duration=%s turns=%d period=%s" % [
				_handle_text(effect.handle), effect.inhibited, effect.stack_count,
				effect.duration, effect.remaining_turns, effect.period
			]
		)


func _build_abilities(root: TreeItem, abilities: Array[GasAbilitySnapshot]) -> void:
	var section: TreeItem = _section(root, "Abilities", abilities.size())
	for ability: GasAbilitySnapshot in abilities:
		var ability_name: String = ability.definition.ability_name if ability.definition != null else "?"
		var last_status: String = (
			GameplayAbilityActivationResult.Status.keys()[ability.last_activation_result.status]
			if ability.last_activation_result != null else "never attempted"
		)
		_row(
			section, ability_name,
			"handle=%s active=%d pending_remove=%s cooldown_active=%s last=%s" % [
				_handle_text(ability.handle), ability.active_count, ability.pending_remove,
				ability.cooldown.active if ability.cooldown != null else false, last_status
			]
		)


func _build_tasks(root: TreeItem, tasks: Array[GasTaskSnapshot]) -> void:
	var section: TreeItem = _section(root, "Tasks", tasks.size())
	for task: GasTaskSnapshot in tasks:
		var type_name: String = task.task_type.get_global_name() if task.task_type != null else "?"
		var state_name: String = GameplayAbilityTask.State.keys()[task.state]
		_row(
			section, type_name,
			"ability_handle=%s state=%s %s" % [_handle_text(task.ability_handle), state_name, task.description]
		)


func _build_cues(root: TreeItem, cues: Array[GasCueSnapshot]) -> void:
	var section: TreeItem = _section(root, "Persistent Cues", cues.size())
	for cue: GasCueSnapshot in cues:
		_row(
			section, String(cue.tag),
			"owning_effect=%s pooled=%d" % [_handle_text(cue.owning_effect_handle), cue.pooled_count]
		)


func _build_refusals(root: TreeItem, refusals: Array[GameplayEffectRefusalRecord]) -> void:
	var section: TreeItem = _section(root, "Recent Refusals", refusals.size())
	for refusal: GameplayEffectRefusalRecord in refusals:
		var status_name: String = GameplayEffectApplicationResult.Status.keys()[refusal.result.status]
		var detail: String = status_name
		if refusal.result.status == GameplayEffectApplicationResult.Status.EVALUATION_FAILED:
			detail += "/" + AttributeEvaluationResult.Status.keys()[refusal.result.evaluation_status]
		_row(
			section, "#%d" % refusal.order,
			"status=%s attribute=%s" % [detail, refusal.result.error_attribute_name]
		)


func _handle_text(handle: Object) -> String:
	return str(handle) if handle != null else "-"
#endregion
