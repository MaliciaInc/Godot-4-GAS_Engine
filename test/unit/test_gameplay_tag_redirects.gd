## Renaming a tag in a project that already ships, and the three things the
## tags file now says about tags beyond listing them.
##
## A rename that broke every asset naming the old tag would be a rename nobody
## performs, so the tags stay wrong forever. What is proved here is that the old
## name still resolves, that a chain somebody built by mistake is refused rather
## than followed forever, that the author is told once instead of once a frame,
## and - the part with teeth - that nothing about resolving writes to the file
## the tags live in.
##
## @meta_license: GAS_Engine Community Use License 1.0
extends GutTest

## Where a rendered tags file is written so it can be read back, instead of the
## project's own.
const SCRATCH_SCRIPT: String = "user://gameplay_tag_declarations_probe.gd"

const OLD: StringName = &"Status.Stun"
const NEW: StringName = &"Status.Stunned"
const NEWER: StringName = &"State.Stunned"

## Whatever the path setting held before a test pointed it at the scratch file.
var _previous_path: Variant = null


func before_each() -> void:
	# Once per run means once per run, and another suite's resolve is another
	# run's worth of saying it. Cleared at both ends so neither this suite nor
	# the next inherits what the other mentioned.
	GameplayTagRedirects.forget()


func after_each() -> void:
	GameplayTagRedirects.forget()
	if _previous_path != null:
		ProjectSettings.set_setting(_setting(), _previous_path)
		_previous_path = null
	if FileAccess.file_exists(SCRATCH_SCRIPT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_SCRIPT))


static func _setting() -> String:
	return GASEngineProjectSettings.PROJECT_SETTINGS_NAME_RESOURCES_TAGS_GENERATED_SCRIPT


## Point the generator at a file this test owns, and put `source` in it.
func _write_scratch(source: String) -> void:
	_previous_path = ProjectSettings.get_setting(
		_setting(), GASEngineProjectSettings.DEFAULT_PATH_TAGS_GENERATED_SCRIPT
	)
	ProjectSettings.set_setting(_setting(), SCRATCH_SCRIPT)
	var file: FileAccess = FileAccess.open(SCRATCH_SCRIPT, FileAccess.WRITE)
	assert_not_null(file, "the scratch file opened for writing")
	file.store_string(source)
	file.close()


## A chain of `hops` renames, `Chain.T0` through `Chain.T<hops>`.
static func _chain(hops: int) -> Dictionary[StringName, StringName]:
	var made: Dictionary[StringName, StringName] = {}
	for step: int in hops:
		made[StringName("Chain.T%d" % step)] = StringName("Chain.T%d" % (step + 1))
	return made


#region Following a rename
## A tag nothing renamed is itself, which is every tag in most projects.
func test_a_tag_nobody_renamed_comes_back_as_itself() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW}

	assert_eq(
		GameplayTagRedirects.resolve(&"Ability.Melee", redirects),
		&"Ability.Melee",
		"nothing points at it, so nothing changes it"
	)


## A rename of a rename resolves to the end, not to the middle.
##
## The middle is a name that was somebody's tag once and is not now. Answering
## with it would hand back a tag the registry does not hold, which is worse than
## answering with the one that arrived.
func test_a_chain_of_renames_resolves_to_the_last_name() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW, NEW: NEWER}

	assert_eq(GameplayTagRedirects.resolve(OLD, redirects), NEWER, "all the way along")
	assert_eq(GameplayTagRedirects.resolve(NEW, redirects), NEWER, "and from the middle")


## A cycle answers with the tag as it arrived.
##
## Two people each renaming the other's tag is how one gets built, and it is a
## mistake rather than a condition: following it forever is how an editor hangs
## on the file it was asked to open.
func test_a_cycle_answers_with_the_tag_as_it_arrived() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW, NEW: OLD}

	assert_eq(GameplayTagRedirects.resolve(OLD, redirects), OLD, "unchanged, not half-followed")
	assert_true(GameplayTagRedirects.mentioned(OLD), "and the author is told about it")


## A chain that leads into a cycle answers with the tag that arrived, not with
## a name from inside the loop.
##
## The case that tells the two apart. A two-tag cycle entered at one of its own
## members happens to leave the walk standing on the tag it started from, so
## answering with wherever the walk stopped looks right there and is wrong the
## moment somebody renames a third tag into it - and the name handed back is one
## the registry does not hold.
func test_a_chain_that_leads_into_a_cycle_still_answers_with_what_arrived() -> void:
	var outside: StringName = &"Status.Stunning"
	var redirects: Dictionary[StringName, StringName] = {outside: OLD, OLD: NEW, NEW: OLD}

	assert_eq(
		GameplayTagRedirects.resolve(outside, redirects), outside,
		"the tag as it arrived, not the one the walk stopped on"
	)


## A chain at the limit is followed and one past it is not.
##
## Both rows, because a limit tested only from the far side is a limit that
## could be off by one in the direction that refuses ordinary work.
##
##     [what it is, how many renames, whether it is followed]
func _chain_lengths() -> Array:
	return [
		["a chain at the limit", GameplayTagRedirects.MAX_DEPTH, true],
		["one rename past it", GameplayTagRedirects.MAX_DEPTH + 1, false],
	]


func test_a_chain_past_the_limit_is_not_followed(
	case: Array = use_parameters(_chain_lengths())
) -> void:
	var described: String = case[0]
	var hops: int = case[1]
	var followed: bool = case[2]

	var expected: StringName = (
		StringName("Chain.T%d" % hops) if followed else StringName("Chain.T0")
	)
	assert_eq(
		GameplayTagRedirects.resolve(&"Chain.T0", _chain(hops)), expected, described
	)


## The author is told once, however many times the tag is resolved.
##
## A redirect hit on every frame of a channelled ability would otherwise print a
## line per frame, and a warning nobody can read is a warning nobody reads.
func test_a_rename_is_mentioned_once_and_then_again_after_forgetting() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW}

	assert_false(GameplayTagRedirects.mentioned(OLD), "nothing said yet")
	GameplayTagRedirects.resolve(OLD, redirects)
	assert_true(GameplayTagRedirects.mentioned(OLD), "said once")
	GameplayTagRedirects.resolve(OLD, redirects)
	assert_true(GameplayTagRedirects.mentioned(OLD), "and not unsaid by asking again")

	GameplayTagRedirects.forget()
	assert_false(
		GameplayTagRedirects.mentioned(OLD),
		"a new run starts over, so somebody sees it once per run rather than once ever"
	)
#endregion


#region Nothing is rewritten
## Resolving a rename does not touch the file the tags live in.
##
## The rule with teeth. A loader that helpfully updated what it read would
## dirty every asset naming an old tag the first time somebody opened the
## project, and put them all in whatever commit came next - a hundred files
## changed by an action nobody took.
func test_resolving_a_rename_never_rewrites_the_tags_file() -> void:
	var path: String = GASEngineProjectSettings.get_generated_tag_script_path()
	var before: String = FileAccess.get_file_as_string(path)

	var redirects: Dictionary[StringName, StringName] = {OLD: NEW, NEW: NEWER}
	GameplayTagRedirects.resolve(OLD, redirects)
	GameplayTagRedirects.resolve(&"Chain.T0", _chain(GameplayTagRedirects.MAX_DEPTH + 1))

	assert_eq(
		FileAccess.get_file_as_string(path), before, "byte for byte as it was"
	)
#endregion


#region What the file declares
## The three declarations survive the round trip through the file.
##
## They are read back as text for the reason the tags are: the file declares a
## global `class_name`, so loading a second copy of it collides with the one
## Godot has already registered.
func test_the_three_declarations_are_read_back_out_of_the_file() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW}
	var restricted: Dictionary[StringName, StringName] = {&"Lyra": &"LyraPlugin"}
	var comments: Dictionary[StringName, String] = {NEW: "Cannot act; movement is stopped."}

	_write_scratch(
		GameplayTagGenerator.render_tags_source(
			[NEW] as Array[StringName], redirects, restricted, comments
		)
	)

	assert_eq(GameplayTagGenerator.redirects_in_file(), redirects, "the renames")
	assert_eq(GameplayTagGenerator.restricted_in_file(), restricted, "the owned branches")
	assert_eq(GameplayTagGenerator.comments_in_file(), comments, "and what each tag is for")
	assert_eq(
		GameplayTagGenerator.tags_in_file(), [NEW] as Array[StringName],
		"and the tags themselves, which the three blocks did not disturb"
	)


## Adding a tag keeps every redirect, owned branch and comment already declared.
##
## The generator renders the whole file, so writing one with the defaults would
## delete all three the first time anybody added a tag - authored work removed
## by an unrelated action, in a file nobody thinks of as theirs to check.
func test_adding_a_tag_keeps_what_the_file_already_declared() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW}
	var restricted: Dictionary[StringName, StringName] = {&"Lyra": &"LyraPlugin"}
	var comments: Dictionary[StringName, String] = {NEW: "Cannot act."}
	_write_scratch(
		GameplayTagGenerator.render_tags_source(
			[NEW] as Array[StringName], redirects, restricted, comments
		)
	)

	var registry: GameplayTagRegistry = GameplayTagRegistry.new()
	registry.tags = [NEW]
	registry.speaks_for_project = true
	assert_eq(registry.add_tag("Ability.Melee"), "Ability.Melee", "the tag was added")

	assert_eq(GameplayTagGenerator.redirects_in_file(), redirects, "the renames survived")
	assert_eq(GameplayTagGenerator.restricted_in_file(), restricted, "so did the branches")
	assert_eq(GameplayTagGenerator.comments_in_file(), comments, "and the comments")
	assert_true(
		GameplayTagGenerator.tags_in_file().has(&"Ability.Melee"), "along with the new tag"
	)
#endregion


#region The rename is in force where it matters
## An asset naming the old tag grants the tag the project has now.
##
## The whole point of a rename that rewrites nothing: the effect naming
## `Status.Stun` is never touched, and what it grants is `Status.Stunned` - so
## the ability that requires the new name finds it, which it would not if the
## runtime held both names as two different tags.
func test_an_old_name_grants_the_tag_the_project_has_now() -> void:
	var redirects: Dictionary[StringName, StringName] = {OLD: NEW}
	_write_scratch(
		GameplayTagGenerator.render_tags_source([NEW] as Array[StringName], redirects)
	)
	# The declared renames are read once and kept, so the file just written has
	# to replace what was read before it existed.
	GameplayTagRedirects.forget()

	var runtime: GameplayTagRuntime = GameplayTagRuntime.new()

	assert_eq(runtime.add(OLD), GameplayTagRuntime.Change.ADDED, "granted by its old name")
	assert_eq(
		runtime.active_tags(), [NEW] as Array[StringName],
		"and held under the one the project has now"
	)
	assert_true(runtime.has(OLD), "asking by the old name finds it")
	assert_true(runtime.has(NEW), "and so does asking by the new one")
	assert_eq(runtime.count(NEW), 1, "held once, not once per name")
	assert_eq(
		runtime.remove(OLD), GameplayTagRuntime.Change.REMOVED,
		"and the effect that granted it can take it off again"
	)


## A project that renamed nothing is not touched by any of this.
func test_a_project_with_no_renames_holds_exactly_what_it_was_given() -> void:
	var runtime: GameplayTagRuntime = GameplayTagRuntime.new()

	runtime.add(OLD)

	assert_eq(runtime.active_tags(), [OLD] as Array[StringName], "the tag as it was given")
#endregion


#region Branches somebody else owns
## The nearest owner answers, not whichever one was declared first.
##
## A plugin owning `Lyra` and a team owning `Lyra.Ability` are both true of
## `Lyra.Ability.Sprint`, and the one worth naming is whoever would actually
## have to define it.
##
##     [what it is called, the tag, who owns it]
func _ownership_cases() -> Array:
	return [
		["inside the nearer branch", &"Lyra.Ability.Sprint", &"TheAbilityTeam"],
		["inside the outer one only", &"Lyra.Effect.Burning", &"LyraPlugin"],
		["the prefix itself", &"Lyra", &"LyraPlugin"],
		["a word that merely starts the same", &"Lyras.Ability", &""],
		["a project's own tag", &"Status.Stunned", &""],
	]


func test_the_owner_of_a_branch_is_the_nearest_one(
	case: Array = use_parameters(_ownership_cases())
) -> void:
	var described: String = case[0]
	var tag: StringName = case[1]
	var expected: StringName = case[2]

	var restricted: Dictionary[StringName, StringName] = {
		&"Lyra": &"LyraPlugin", &"Lyra.Ability": &"TheAbilityTeam"
	}
	assert_eq(GameplayTagRestrictions.owner_of(tag, restricted), expected, described)


## Adding a tag in somebody else's branch is refused, and their name is in the
## refusal.
##
## Refused rather than warned about: a tag added under a prefix its owner
## defines is one name with two definitions, and the second one arrives with
## their next update.
func test_the_registry_refuses_a_tag_in_somebody_else_s_branch() -> void:
	var restricted: Dictionary[StringName, StringName] = {&"Lyra": &"LyraPlugin"}
	var registry: GameplayTagRegistry = GameplayTagRegistry.new()

	var refused: String = registry.add_tag("Lyra.Ability.Sprint", restricted)

	assert_true(refused.begins_with(GameplayTagRegistry.ERROR_PREFIX), "it was refused")
	assert_true(refused.contains("LyraPlugin"), "naming who to ask")
	assert_false(registry.has_tag(&"Lyra.Ability.Sprint"), "and it was not added")


## A project that declares no owned branches has none of this happen to it.
func test_a_project_with_no_owned_branches_refuses_nothing() -> void:
	var registry: GameplayTagRegistry = GameplayTagRegistry.new()

	var added: String = registry.add_tag("Lyra.Ability.Sprint", {})

	assert_eq(added, "Lyra.Ability.Sprint", "added, because nobody owns it")
	assert_true(registry.has_tag(&"Lyra.Ability.Sprint"), "and it is really there")
#endregion
