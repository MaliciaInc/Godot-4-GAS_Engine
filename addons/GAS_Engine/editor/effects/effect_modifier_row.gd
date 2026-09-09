## One modifier, as a row of fields.
##
## Everything a modifier says in one line: which attribute, how, how much, and
## where in the composition. Built in code rather than as a scene because a row
## is created and destroyed as an author adds and removes them, and a scene for
## something that only ever appears in a list is a file to keep in step with
## the code that fills it.
##
## Holds no state of its own. Every field writes straight through to the
## document, and the row is rebuilt from the effect afterwards - so what is on
## screen is what is in the Resource, always, rather than usually.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
@tool
class_name EffectModifierRow extends HBoxContainer

const REMOVE_TEXT: String = "×"
const REMOVE_HINT: String = "Remove this modifier"
const ATTRIBUTE_HINT: String = "Which attribute this changes"
const AMOUNT_HINT: String = "What it is worth at level one"
const CHANNEL_HINT: String = "Where in the composition it lands"

## This row's place in the effect's modifier list, which is how every edit says
## which modifier it is about.
var index: int = 0

var document: GameplayEffectDocument = null

var _attribute: LineEdit = null
var _operation: OptionButton = null
var _amount: SpinBox = null
var _channel: SpinBox = null


## Build a row for one modifier of one document.
static func create(
	for_document: GameplayEffectDocument, at_index: int
) -> EffectModifierRow:
	var row: EffectModifierRow = EffectModifierRow.new()
	row.document = for_document
	row.index = at_index
	return row


func _ready() -> void:
	_attribute = LineEdit.new()
	_attribute.placeholder_text = ATTRIBUTE_HINT
	_attribute.tooltip_text = ATTRIBUTE_HINT
	_attribute.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attribute.text_submitted.connect(_on_attribute_named)
	add_child(_attribute)

	_operation = OptionButton.new()
	for name: String in GameplayEffectModifier.Operation.keys():
		_operation.add_item(name.capitalize())
	_operation.item_selected.connect(_on_operation_chosen)
	add_child(_operation)

	_amount = SpinBox.new()
	_amount.allow_greater = true
	_amount.allow_lesser = true
	_amount.step = 0.01
	_amount.tooltip_text = AMOUNT_HINT
	_amount.value_changed.connect(_on_amount_typed)
	add_child(_amount)

	_channel = SpinBox.new()
	_channel.max_value = AttributeAggregateMath.CHANNELS - 1
	_channel.tooltip_text = CHANNEL_HINT
	_channel.value_changed.connect(_on_channel_typed)
	add_child(_channel)

	var remove: Button = Button.new()
	remove.text = REMOVE_TEXT
	remove.tooltip_text = REMOVE_HINT
	remove.pressed.connect(_on_remove_pressed)
	add_child(remove)

	show_what_is_there()


## Put the modifier's own values into the fields.
##
## Called after building and after anything else changes the effect, because
## the effect is the model: a row showing what somebody typed rather than what
## was stored is a row that lies the first time an edit is clamped.
func show_what_is_there() -> void:
	var modifier: GameplayEffectModifier = document.modifier_at(index) if document != null else null
	if modifier == null or _attribute == null:
		return
	_attribute.text = String(modifier.attribute_name)
	_operation.select(int(modifier.operation))
	# Without a signal, in both fields: filling a SpinBox emits value_changed,
	# which writes back to the document, which announces a change, which
	# rebuilds the rows - and fills this field again.
	_channel.set_value_no_signal(modifier.evaluation_channel)
	var magnitude: GameplayScalableMagnitude = document.magnitude_at(index)
	if magnitude != null and magnitude.value != null:
		_amount.set_value_no_signal(magnitude.value.value)


func _on_attribute_named(named: String) -> void:
	var reference: GameplayAttributeRef = GameplayAttributeRef.new()
	reference.attribute_name = StringName(named)
	document.set_modifier_attribute(index, reference)


func _on_operation_chosen(chosen: int) -> void:
	document.set_modifier_operation(index, chosen as GameplayEffectModifier.Operation)


func _on_amount_typed(typed: float) -> void:
	document.set_modifier_amount(index, typed)


func _on_channel_typed(typed: float) -> void:
	document.set_modifier_channel(index, int(typed))
	show_what_is_there()


func _on_remove_pressed() -> void:
	document.remove_modifier(index)
