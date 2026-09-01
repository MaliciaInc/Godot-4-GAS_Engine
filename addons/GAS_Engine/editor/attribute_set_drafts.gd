## The uncompiled attribute-set drafts, as a typed model over a ConfigFile.
##
## The dashboard tab reached into the ConfigFile at forty-two places, each with
## its own explicit save and its own handling of the two shapes an entry can
## take. That is four decisions repeated forty-two times, and a forgotten save
## loses a designer's work silently.
##
## Every mutation here persists. Every read returns a typed Entry, so the
## legacy shape - a bare float, from before icons existed - is decoded once,
## here, rather than at each call site.
##
## @meta_addon: GAS_Engine
## @meta_license: MIT

@tool
class_name AttributeSetDrafts extends RefCounted


## The section name a ConfigFile reserves for its own settings, so a set may not
## be called this.
const RESERVED_SECTION: String = "Settings"

## The key that marks a set as created rather than an attribute of it.
const INITIALISED_KEY: String = "_initialized"

## Said out loud, because a designer whose work did not reach disk has no
## other way to find out.
const SAVE_FAILED: String = "GAS_Engine: could not save the attribute drafts to %s (%s)."
const LOAD_FAILED: String = "GAS_Engine: could not read the attribute drafts at %s (%s)."

const VALUE_KEY: String = "value"
const ICON_KEY: String = "icon"
## The icon catalogue owns this name; a second constant holding the same
## string is a second place to change it.
const DEFAULT_ICON: String = AttributeIcons.DEFAULT_NAME


## One drafted attribute: its starting value and the icon it shows.
class Entry extends RefCounted:
	var value: float = 0.0
	var icon: String = DEFAULT_ICON

	static func of(entry_value: float, entry_icon: String = DEFAULT_ICON) -> Entry:
		var entry: Entry = Entry.new()
		entry.value = entry_value
		entry.icon = entry_icon
		return entry

	func to_dictionary() -> Dictionary:
		return {VALUE_KEY: value, ICON_KEY: icon}


var _config: ConfigFile = ConfigFile.new()


#region Persistence
## Read the drafts. A missing file is the normal first-run state, not an error.
func load_from_disk() -> void:
	var path: String = GASEngineProjectSettings.get_attributes_draft_config_path()
	var status: Error = _config.load(path)
	if status != OK and status != ERR_FILE_NOT_FOUND:
		push_error(LOAD_FAILED % [path, error_string(status)])


## Persist. Private because no caller should have to remember it: every mutation
## below calls it, and a mutation that did not would lose work silently.
##
## The directory does not exist until something writes there, and the error was
## discarded, so a failed write was the very silent loss this exists to prevent.
func _save() -> void:
	var path: String = GASEngineProjectSettings.get_attributes_draft_config_path()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var status: Error = _config.save(path)
	if status != OK:
		push_error(SAVE_FAILED % [path, error_string(status)])
#endregion


#region Sets
## Every drafted set, excluding the ConfigFile's reserved section.
func set_names() -> Array[String]:
	var names: Array[String] = []
	for section: String in _config.get_sections():
		if section != RESERVED_SECTION:
			names.append(section)
	return names


func has_set(set_name: String) -> bool:
	return _config.has_section(set_name)


## Create an empty set. Returns false when the name is unusable, reserved or
## taken.
##
## Unusable means GDScript could not accept it: the name is written into
## `class_name <name>AttributeSet`, so `My Set` would generate a script that
## does not parse. is_valid_identifier is Godot's own rule for what its parser
## takes, and an empty name fails it too.
func create_set(set_name: String) -> bool:
	if not set_name.is_valid_identifier() or set_name == RESERVED_SECTION or has_set(set_name):
		return false
	_config.set_value(set_name, INITIALISED_KEY, true)
	_save()
	return true


## Rename a set, carrying its attributes over. Returns false when the new name
## is unusable, reserved or taken. See `create_set` for what unusable means.
func rename_set(old_name: String, new_name: String) -> bool:
	if not new_name.is_valid_identifier() or new_name == RESERVED_SECTION or has_set(new_name):
		return false
	if not has_set(old_name):
		return false
	for key: String in _config.get_section_keys(old_name):
		_config.set_value(new_name, key, _config.get_value(old_name, key))
	_config.erase_section(old_name)
	_save()
	return true


## Copy a set under a free name, and return that name.
##
## Dictionaries are deep-copied. A shallow copy would leave the two sets sharing
## every entry, so editing one would silently edit the other.
func duplicate_set(set_name: String) -> String:
	if not has_set(set_name):
		return ""
	var copy_name: String = _free_name(set_name + "Copy")
	for key: String in _config.get_section_keys(set_name):
		var raw: Variant = _config.get_value(set_name, key)
		if raw is Dictionary:
			var stored: Dictionary = raw
			raw = stored.duplicate(true)
		_config.set_value(copy_name, key, raw)
	_save()
	return copy_name


func delete_set(set_name: String) -> void:
	if has_set(set_name):
		_config.erase_section(set_name)
		_save()


func _free_name(preferred: String) -> String:
	if not has_set(preferred):
		return preferred
	var counter: int = 2
	while has_set(preferred + str(counter)):
		counter += 1
	return preferred + str(counter)
#endregion


#region Attributes
## The attributes of a set, in draft order, without the initialisation marker.
func attribute_names(set_name: String) -> Array[String]:
	var names: Array[String] = []
	if not has_set(set_name):
		return names
	for key: String in _config.get_section_keys(set_name):
		if key != INITIALISED_KEY:
			names.append(key)
	return names


func has_attribute(set_name: String, key: String) -> bool:
	return _config.has_section_key(set_name, key)


## Read one attribute, decoding whichever shape it was stored in.
##
## Entries written before icons existed are bare floats. They are migrated on
## read so the rest of the code never sees the old shape.
func entry(set_name: String, key: String) -> Entry:
	if not has_attribute(set_name, key):
		return Entry.new()

	# A draft is a file a human can edit, so it may hold anything. Every value
	# is checked before it is trusted, in one place, rather than through two
	# guard helpers that were the same template written twice.
	var decoded: Entry = Entry.new()
	var raw: Variant = _config.get_value(set_name, key)

	var carried: Variant = raw
	if raw is Dictionary:
		var stored: Dictionary = raw
		carried = stored.get(VALUE_KEY)
		var icon_value: Variant = stored.get(ICON_KEY)
		if icon_value is String:
			var icon_text: String = icon_value
			decoded.icon = icon_text

	if carried is float:
		var decimal: float = carried
		decoded.value = decimal
	elif carried is int:
		var whole: int = carried
		decoded.value = float(whole)

	if not raw is Dictionary:
		# Written before icons existed. Migrated on read, so nothing downstream
		# ever sees the old shape.
		put(set_name, key, decoded)
	return decoded


func put(set_name: String, key: String, value: Entry) -> void:
	_config.set_value(set_name, key, value.to_dictionary())
	_save()


## Add a new attribute. Returns false when the name is unusable or taken.
##
## The name is written into `@export var <name>: AttributeData`, so it has to be
## something GDScript will accept.
func add_attribute(set_name: String, key: String, value: Entry) -> bool:
	if not key.is_valid_identifier() or has_attribute(set_name, key):
		return false
	put(set_name, key, value)
	return true


## Rename an attribute, keeping its value and icon. Returns false when the new
## name is unusable, reserved or taken.
func rename_attribute(set_name: String, old_key: String, new_key: String) -> bool:
	if (
		not new_key.is_valid_identifier()
		or new_key == INITIALISED_KEY
		or has_attribute(set_name, new_key)
	):
		return false
	if not has_attribute(set_name, old_key):
		return false
	var carried: Entry = entry(set_name, old_key)
	_config.erase_section_key(set_name, old_key)
	put(set_name, new_key, carried)
	return true


## Copy an attribute under a free name, and return that name.
func duplicate_attribute(set_name: String, key: String) -> String:
	if not has_attribute(set_name, key):
		return ""
	var copy_key: String = key
	var counter: int = 2
	while has_attribute(set_name, copy_key):
		copy_key = key + str(counter)
		counter += 1
	put(set_name, copy_key, entry(set_name, key))
	return copy_key


func delete_attribute(set_name: String, key: String) -> void:
	if has_attribute(set_name, key):
		_config.erase_section_key(set_name, key)
		_save()
#endregion
