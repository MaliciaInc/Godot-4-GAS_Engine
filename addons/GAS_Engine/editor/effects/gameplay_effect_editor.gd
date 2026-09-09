## The window an effect is authored in.
##
## A projection of GameplayEffectDocument and nothing more: every field writes
## through to the document, and the whole screen is rebuilt from the effect
## afterwards. There is no state here that the Resource does not have, which is
## what makes "what is on screen is what will be saved" true rather than
## usually true.
##
## Rebuilt wholesale rather than patched. Patching means every edit has to know
## which parts of the screen it invalidates, and the parts nobody thought of are
## the ones that go stale.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name GameplayEffectEditor extends VBoxContainer

## Named for what it saves rather than just "Save": this screen sits in a
## bottom panel beside other things that can be saved.
const SAVE_TEXT: String = "Save effect"
const ADD_MODIFIER_TEXT: String = "Add modifier"
const ADD_COMPONENT_TEXT: String = "Add component"
const NOTHING_OPEN: String = "No effect open."
const NOTHING_WRONG: String = "Nothing to report."
const DURATION_LABEL: String = "Duration"
const PERIOD_LABEL: String = "Period"
const STACK_LABEL: String = "Stack limit"

var document: GameplayEffectDocument = GameplayEffectDocument.new()

var _policy: OptionButton = null
var _duration: SpinBox = null
var _period: SpinBox = null
var _stacking: OptionButton = null
var _stack_limit: SpinBox = null
var _modifiers: VBoxContainer = null
var _components: VBoxContainer = null
var _cues: VBoxContainer = null
var _findings: Label = null
var _menu: EffectComponentMenu = null


func _ready() -> void:
	_build()
	document.changed.connect(refresh)
	refresh()


## Open an effect and show it.
## @composer
func open(path: String) -> bool:
	var opened: bool = document.open(path)
	refresh()
	return opened


## @composer
func save() -> bool:
	return document.save()


#region Building the shell
func _build() -> void:
	var header: HBoxContainer = HBoxContainer.new()
	_policy = OptionButton.new()
	for name: String in GameplayEffect.DurationPolicy.keys():
		_policy.add_item(name.capitalize())
	_policy.item_selected.connect(_on_policy_chosen)
	header.add_child(_policy)
	header.add_child(_labelled(DURATION_LABEL))
	_duration = _seconds_field(_on_duration_typed)
	header.add_child(_duration)
	header.add_child(_labelled(PERIOD_LABEL))
	_period = _seconds_field(_on_period_typed)
	header.add_child(_period)
	add_child(header)

	var stacking_row: HBoxContainer = HBoxContainer.new()
	_stacking = OptionButton.new()
	for name: String in GameplayEffect.StackingType.keys():
		_stacking.add_item(name.capitalize())
	_stacking.item_selected.connect(_on_stacking_chosen)
	stacking_row.add_child(_stacking)
	stacking_row.add_child(_labelled(STACK_LABEL))
	_stack_limit = SpinBox.new()
	_stack_limit.allow_greater = true
	_stack_limit.value_changed.connect(_on_stack_limit_typed)
	stacking_row.add_child(_stack_limit)
	add_child(stacking_row)

	_modifiers = VBoxContainer.new()
	add_child(_modifiers)
	add_child(_button(ADD_MODIFIER_TEXT, _on_add_modifier_pressed))

	_components = VBoxContainer.new()
	add_child(_components)
	add_child(_button(ADD_COMPONENT_TEXT, _on_add_component_pressed))

	_cues = VBoxContainer.new()
	add_child(_cues)

	_findings = Label.new()
	_findings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_findings)

	add_child(_button(SAVE_TEXT, _on_save_pressed))

	_menu = EffectComponentMenu.new()
	_menu.component_chosen.connect(_on_component_chosen)
	add_child(_menu)


func _labelled(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	return label


func _seconds_field(on_typed: Callable) -> SpinBox:
	var field: SpinBox = SpinBox.new()
	field.allow_greater = true
	field.step = 0.1
	field.value_changed.connect(on_typed)
	return field


func _button(text: String, on_pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button
#endregion


#region Showing what is there
## Put the whole effect on screen again.
##
## Everything, every time. The alternative is each edit knowing which parts of
## the screen it invalidated, and the parts nobody thought of going stale.
func refresh() -> void:
	if _findings == null:
		return
	_show_header()
	_show_list(_modifiers, _modifier_rows())
	_show_list(_components, _component_rows())
	_show_list(_cues, _cue_rows())
	_show_findings()


func _show_header() -> void:
	var effect: GameplayEffect = document.effect
	var open: bool = effect != null
	_policy.disabled = not open
	_duration.editable = open
	_period.editable = open
	_stacking.disabled = not open
	_stack_limit.editable = open
	if not open:
		return
	_policy.select(int(effect.policy))
	_duration.set_value_no_signal(effect.duration)
	_period.set_value_no_signal(effect.period)
	_stacking.select(int(effect.stacking_type))
	_stack_limit.set_value_no_signal(effect.stack_limit_count)


## Replace the children of one list with the rows it should have.
func _show_list(into: VBoxContainer, rows: Array[Control]) -> void:
	for existing: Node in into.get_children():
		into.remove_child(existing)
		existing.queue_free()
	for row: Control in rows:
		into.add_child(row)


func _modifier_rows() -> Array[Control]:
	var rows: Array[Control] = []
	if document.effect == null:
		return rows
	for index: int in document.effect.modifiers.size():
		rows.append(EffectModifierRow.create(document, index))
	return rows


## Components and cues are shown as what they are and removed as a whole.
##
## Editing what is inside one is the inspector's job: a component is a Resource
## with its own exported fields, and a second editor for those fields would be a
## second place they can be wrong.
func _component_rows() -> Array[Control]:
	var rows: Array[Control] = []
	if document.effect == null:
		return rows
	for index: int in document.effect.components.size():
		var held: GameplayEffectComponent = document.effect.components[index]
		if held == null:
			continue
		rows.append(_removable(EffectComponentMenu.readable_name(held.get_script()), index, true))
	return rows


func _cue_rows() -> Array[Control]:
	var rows: Array[Control] = []
	if document.effect == null:
		return rows
	for index: int in document.effect.cues.size():
		var binding: GameplayCueBinding = document.effect.cues[index]
		if binding == null:
			continue
		rows.append(_removable(String(binding.cue_tag), index, false))
	return rows


func _removable(text: String, index: int, is_component: bool) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = _labelled(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var remove: Button = Button.new()
	remove.text = EffectModifierRow.REMOVE_TEXT
	if is_component:
		remove.pressed.connect(func() -> void: document.remove_component(index))
	else:
		remove.pressed.connect(func() -> void: document.remove_cue(index))
	row.add_child(remove)
	return row


## What the engine would say about this effect, as it is now.
func _show_findings() -> void:
	if document.effect == null:
		_findings.text = NOTHING_OPEN
		return
	var lines: PackedStringArray = PackedStringArray()
	for finding: GameplayAssetValidationResult in document.validation():
		lines.append(_said(finding))
	_findings.text = "\n".join(lines) if lines.size() > 0 else NOTHING_WRONG


## One finding, in a sentence.
##
## Worded here rather than on the result, because what the engine found and
## how to say it to a person are two things: the same finding is a red line in
## an inspector and a log entry in a build.
func _said(finding: GameplayAssetValidationResult) -> String:
	var severity: String = GameplayAssetValidationResult.Severity.keys()[
		int(finding.severity)
	]
	var code: String = GameplayAssetValidationResult.Code.keys()[int(finding.code)]
	var where: String = finding.field if not finding.field.is_empty() else "the effect"
	return "%s: %s (%s)" % [severity.capitalize(), code.capitalize(), where]
#endregion


#region What the fields do
func _on_policy_chosen(chosen: int) -> void:
	document.set_policy(chosen as GameplayEffect.DurationPolicy)


func _on_duration_typed(typed: float) -> void:
	document.set_duration(typed)


func _on_period_typed(typed: float) -> void:
	document.set_period(typed)


func _on_stacking_chosen(chosen: int) -> void:
	document.set_stacking(
		chosen as GameplayEffect.StackingType, int(_stack_limit.value)
	)


func _on_stack_limit_typed(typed: float) -> void:
	if document.effect == null:
		return
	document.set_stacking(document.effect.stacking_type, int(typed))


func _on_save_pressed() -> void:
	save()


func _on_add_modifier_pressed() -> void:
	document.add_modifier()


func _on_add_component_pressed() -> void:
	_menu.offer_for(document)
	_menu.popup_centered()


func _on_component_chosen(component_script: Script) -> void:
	var made: GameplayEffectComponent = component_script.new() as GameplayEffectComponent
	if made != null:
		document.add_component(made)
#endregion
