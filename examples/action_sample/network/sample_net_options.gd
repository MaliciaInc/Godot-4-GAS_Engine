## What the two sample processes were asked for on the command line.
##
##     --server                 be the authority
##     --client=<host>:<port>   be a client, and where to find the authority
##     --port=<port>            which port the authority listens on
##     --automation             run the scenario and exit rather than staying up
##     --out=<path>             where to write what this process ended with
##
## Read from the arguments after `--`, which is where Godot puts what the game
## was asked for rather than what the engine was. A flag that reaches the engine
## instead is a flag the engine refuses, which is a confusing way to find out
## you typed it in the wrong place.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name SampleNetOptions extends RefCounted

const SERVER: String = "--server"
const CLIENT: String = "--client="
const PORT: String = "--port="
const AUTOMATION: String = "--automation"
const OUT: String = "--out="

var is_server: bool = false
var is_client: bool = false
var address: String = "127.0.0.1"
var port: int = SampleNetSession.DEFAULT_PORT

## Whether to run the scenario and stop.
##
## False leaves the process up, which is what a person wanting to watch it
## wants and what a harness must never get: a run that does not end is a run
## nobody can wait for.
var automation: bool = false

## Where the ending is written. A file, because two processes writing their
## conclusions to one console is two conclusions nobody can tell apart.
var out: String = "user://sample_net.json"


static func read(arguments: PackedStringArray = PackedStringArray()) -> SampleNetOptions:
	var given: PackedStringArray = arguments
	if given.is_empty():
		given = PackedStringArray(OS.get_cmdline_user_args())

	var options: SampleNetOptions = SampleNetOptions.new()
	for argument: String in given:
		if argument == SERVER:
			options.is_server = true
		elif argument == AUTOMATION:
			options.automation = true
		elif argument.begins_with(CLIENT):
			options.is_client = true
			options._where(argument.trim_prefix(CLIENT))
		elif argument.begins_with(PORT):
			options.port = int(argument.trim_prefix(PORT))
		elif argument.begins_with(OUT):
			options.out = argument.trim_prefix(OUT)
	return options


## How this run was asked for, for the message that says it was asked wrong.
func spelling() -> String:
	if is_server:
		return SERVER
	if is_client:
		return "%s%s:%d" % [CLIENT, address, port]
	return "neither a server nor a client"


## `host:port`, or just a host, or just a port.
##
## All three, because a sample somebody is running by hand is a sample somebody
## types half of. A bare number is a port, since no host is a number alone.
func _where(said: String) -> void:
	if said.is_empty():
		return
	if said.is_valid_int():
		port = int(said)
		return
	var parts: PackedStringArray = said.split(":")
	address = parts[0]
	if parts.size() > 1 and parts[1].is_valid_int():
		port = int(parts[1])
