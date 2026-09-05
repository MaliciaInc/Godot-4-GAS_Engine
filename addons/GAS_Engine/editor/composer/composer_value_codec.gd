## Turning a value into GDScript source, and source back into a value.
##
## Only literals, and only the ones that survive the round trip unchanged. A
## control that offers to edit a value has to be able to write what it holds and
## read back what somebody typed; if either direction loses meaning, the file
## and the control start disagreeing and the file is the one that runs.
##
## Nothing here executes anything. No `Expression`, no `load()`, no resolving an
## identifier - a codec that evaluated source would make opening a file in the
## Composer a way to run it. Anything it cannot read as a plain literal comes
## back `ok = false`, and the caller leaves the text alone as an expression the
## person wrote.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerValueCodec extends RefCounted

const OK: String = "ok"
const VALUE: String = "value"

const QUOTE: String = "\""
const NAME_MARK: String = "&"
const PATH_MARK: String = "^"
const PRELOAD_OPEN: String = "preload(\""
const PRELOAD_SHUT: String = "\")"


#region Writing
## The source text for a value, or "" when there is none this codec can write.
##
## An empty answer is not a failure to be papered over: it means the caller must
## keep whatever the file already said. A Resource nobody has saved has no path
## to name, and inventing one would write a line that cannot load.
static func encode_variant(value: Variant, type_name: StringName = &"") -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var number: float = value
			return _float_text(number)
		TYPE_STRING:
			var text: String = value
			return _quoted(text, type_name)
		TYPE_STRING_NAME:
			var named: StringName = value
			return NAME_MARK + QUOTE + _escaped(String(named)) + QUOTE
		TYPE_NODE_PATH:
			var path: NodePath = value
			return PATH_MARK + QUOTE + _escaped(String(path)) + QUOTE
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, \
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return "%s%s" % [type_string(typeof(value)), str(value)]
		TYPE_COLOR:
			var shade: Color = value
			return _color_text(shade)
		TYPE_OBJECT:
			return _resource_text(value)
	return ""


## A float always carries its point, so `0` written for a float parameter does
## not read back as an int and quietly change the call's overload.
static func _float_text(value: float) -> String:
	var written: String = str(value)
	return written if written.contains(".") or written.contains("e") else written + ".0"


static func _quoted(value: String, type_name: StringName) -> String:
	if type_name == ComposerTypes.STRING_NAME:
		return NAME_MARK + QUOTE + _escaped(value) + QUOTE
	if type_name == ComposerTypes.NODE_PATH:
		return PATH_MARK + QUOTE + _escaped(value) + QUOTE
	return QUOTE + _escaped(value) + QUOTE


static func _escaped(value: String) -> String:
	return value.replace("\\", "\\\\").replace(QUOTE, "\\" + QUOTE)


## The digits a Color component actually carries.
##
## A Color holds float32s and everything else here is a float64, so `str()` on a
## component prints the error of the conversion: `0.1` comes back
## `0.10000000149012`. Writing that is the tool rewriting every colour in an
## ability with fourteen digits of noise the moment somebody opens the card that
## holds one - a diff nobody made, on a line nobody touched.
const COLOR_DIGITS: int = 7


static func _color_component(value: float) -> String:
	var written: String = String.num(value, COLOR_DIGITS)
	# Trailing zeros are the rounding showing through, not precision.
	if written.contains("."):
		written = written.rstrip("0")
		if written.ends_with("."):
			written += "0"
	return written


static func _color_text(value: Color) -> String:
	return "%s(%s, %s, %s, %s)" % [
		ComposerTypes.COLOR,
		_color_component(value.r), _color_component(value.g),
		_color_component(value.b), _color_component(value.a),
	]


## A Resource is named by the path it is saved at, and preloaded so the exporter
## and the parser both see it. One with no path is not writable at all.
static func _resource_text(value: Variant) -> String:
	if not value is Resource:
		return ""
	var resource: Resource = value
	if resource.resource_path.is_empty():
		return ""
	return PRELOAD_OPEN + resource.resource_path + PRELOAD_SHUT
#endregion


## What this argument is written as when Composer creates the call.
##
## The engine's own default first, because a method that declares one has said
## what it means by "not given". A value the codec cannot write - a Resource
## nobody saved - falls back to the type's zero rather than to nothing: an
## argument left out is a call that does not compile.
static func default_for(
	field: ComposerNode.Field, defaults: Array, at: int
) -> String:
	if at >= 0 and at < defaults.size():
		var written: String = encode_variant(defaults[at], field.type_name)
		if not written.is_empty():
			return written
	return ComposerTypes.default_expression(field.type_name, field.variant_type)


#region Reading
static func parse_bool(source: String) -> Dictionary:
	var text: String = source.strip_edges()
	if text == "true":
		return _found(true)
	if text == "false":
		return _found(false)
	return _refused()


static func parse_int(source: String) -> Dictionary:
	var text: String = source.strip_edges()
	if not text.is_valid_int():
		return _refused()
	return _found(text.to_int())


static func parse_float(source: String) -> Dictionary:
	var text: String = source.strip_edges()
	if not text.is_valid_float():
		return _refused()
	return _found(text.to_float())


static func parse_string(source: String) -> Dictionary:
	return _quoted_body(source.strip_edges(), "")


static func parse_string_name(source: String) -> Dictionary:
	var read: Dictionary = _quoted_body(source.strip_edges(), NAME_MARK)
	if not read[OK]:
		return read
	var body: String = read[VALUE]
	return _found(StringName(body))


static func parse_node_path(source: String) -> Dictionary:
	var read: Dictionary = _quoted_body(source.strip_edges(), PATH_MARK)
	if not read[OK]:
		return read
	var body: String = read[VALUE]
	return _found(NodePath(body))


static func parse_vector2(source: String, integer: bool = false) -> Dictionary:
	var parts: Array[float] = _components(source, String(ComposerTypes.VECTOR2I if integer else ComposerTypes.VECTOR2), 2)
	if parts.is_empty():
		return _refused()
	if integer:
		return _found(Vector2i(int(parts[0]), int(parts[1])))
	return _found(Vector2(parts[0], parts[1]))


static func parse_vector3(source: String, integer: bool = false) -> Dictionary:
	var parts: Array[float] = _components(source, String(ComposerTypes.VECTOR3I if integer else ComposerTypes.VECTOR3), 3)
	if parts.is_empty():
		return _refused()
	if integer:
		return _found(Vector3i(int(parts[0]), int(parts[1]), int(parts[2])))
	return _found(Vector3(parts[0], parts[1], parts[2]))


static func parse_vector4(source: String, integer: bool = false) -> Dictionary:
	var parts: Array[float] = _components(source, String(ComposerTypes.VECTOR4I if integer else ComposerTypes.VECTOR4), 4)
	if parts.is_empty():
		return _refused()
	if integer:
		return _found(
			Vector4i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]))
		)
	return _found(Vector4(parts[0], parts[1], parts[2], parts[3]))


static func parse_color(source: String) -> Dictionary:
	var parts: Array[float] = _components(source, String(ComposerTypes.COLOR), 4)
	if parts.is_empty():
		return _refused()
	# Built by component rather than through the constructor: every value here
	# came out of the text being read, so there is nothing to construct from.
	var made: Color = Color.BLACK
	made.r = parts[0]
	made.g = parts[1]
	made.b = parts[2]
	made.a = parts[3]
	return _found(made)


## Whether a field's text is a literal this codec could read.
##
## Asked before offering a typed control: a field holding `pick.target_data` is
## an expression, and a SpinBox over it would be a control that cannot show what
## is there and would destroy it the moment it was touched.
static func is_literal(field: ComposerNode.Field) -> bool:
	if field == null:
		return false
	return read_as(field.type_name, field.display)[OK]


## What that text means as that type, or a refusal.
##
## Public because a control has to show the value, not only know that one is
## there: a SpinBox needs the number, and asking twice - once "is this a
## number" and once "what number" - would be two readings of one string that
## can disagree.
static func read_as(type_name: StringName, text: String) -> Dictionary:
	if type_name == ComposerTypes.BOOL:
		return parse_bool(text)
	if type_name == ComposerTypes.INT:
		return parse_int(text)
	if type_name == ComposerTypes.FLOAT:
		return parse_float(text)
	if type_name == ComposerTypes.STRING:
		return parse_string(text)
	if type_name == ComposerTypes.STRING_NAME:
		return parse_string_name(text)
	if type_name == ComposerTypes.NODE_PATH:
		return parse_node_path(text)
	if type_name == ComposerTypes.VECTOR2:
		return parse_vector2(text)
	if type_name == ComposerTypes.VECTOR2I:
		return parse_vector2(text, true)
	if type_name == ComposerTypes.VECTOR3:
		return parse_vector3(text)
	if type_name == ComposerTypes.VECTOR3I:
		return parse_vector3(text, true)
	if type_name == ComposerTypes.VECTOR4:
		return parse_vector4(text)
	if type_name == ComposerTypes.VECTOR4I:
		return parse_vector4(text, true)
	if type_name == ComposerTypes.COLOR:
		return parse_color(text)
	return _refused()


## The body of `&"..."`, `^"..."` or `"..."`, with the mark this call expects.
static func _quoted_body(text: String, mark: String) -> Dictionary:
	var body: String = text
	if not mark.is_empty():
		if not body.begins_with(mark):
			return _refused()
		body = body.substr(mark.length())
	elif body.begins_with(NAME_MARK) or body.begins_with(PATH_MARK):
		return _refused()

	if body.length() < 2 or not body.begins_with(QUOTE) or not body.ends_with(QUOTE):
		return _refused()

	# Beginning and ending with a quote is not enough to be one string.
	# `"fire" if hot else "ice"` does both, and reading it as a literal turns a
	# working expression into the text `"fire\" if hot else \"ice"` the moment
	# anybody touches that argument. A well-formed body is one that survives
	# being unescaped and escaped again; that one does not.
	var inside: String = body.substr(1, body.length() - 2)
	var read: String = _unescaped(inside)
	if _escaped(read) != inside:
		return _refused()
	return _found(read)


static func _unescaped(value: String) -> String:
	return value.replace("\\" + QUOTE, QUOTE).replace("\\\\", "\\")


## The numbers inside `Name(a, b, ...)`, or nothing when the shape is not that.
##
## Refused rather than guessed when a component is not a plain number: `Vector2(x,
## 0.0)` mentions something this codec cannot resolve, and a control built over
## it would show a zero the file does not contain.
static func _components(source: String, prefix: String, wanted: int) -> Array[float]:
	var text: String = source.strip_edges()
	if not text.begins_with(prefix + "(") or not text.ends_with(")"):
		return []
	var inside: String = text.substr(
		prefix.length() + 1, text.length() - prefix.length() - 2
	)
	var parts: PackedStringArray = inside.split(",")
	if parts.size() != wanted:
		return []

	var numbers: Array[float] = []
	for part: String in parts:
		var one: String = part.strip_edges()
		if not one.is_valid_float():
			return []
		numbers.append(one.to_float())
	return numbers


static func _found(value: Variant) -> Dictionary:
	return {OK: true, VALUE: value}


static func _refused() -> Dictionary:
	return {OK: false, VALUE: null}
#endregion
