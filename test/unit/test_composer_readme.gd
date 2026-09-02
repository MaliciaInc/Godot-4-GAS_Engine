## What the page a stranger reads promises, held against the code.
##
## Documentation is a declared authority sitting beside the tree, which is the
## shape this project keeps closing. The README tells somebody deciding whether
## to use the Composer what it can and cannot draw, and the subset has already
## been widened twice - so without this the page goes quietly out of date and
## the person it misleads is the one furthest from being able to check.
##
## @meta_license: MIT
extends GutTest

const README: String = "res://README.md"


## Every construction the subset refuses is named in the README.
##
## Documentation is a declared authority sitting beside the code, and this is
## the only thing that keeps one honest. The day somebody widens the subset -
## and it has been widened twice already - the page that tells people what the
## Composer cannot draw stops being true, silently, and the person it misleads
## is the one deciding whether to use the tool at all.
func test_the_readme_names_every_construction_the_subset_refuses() -> void:
	var written: String = FileAccess.get_file_as_string(README)

	for rule: Array in ComposerSubset.REFUSED:
		# The word itself, not the shape the classifier looks for: the table
		# spells an inline function two ways because a person might write it
		# either way, and the README is not a parser.
		var written_as: String = rule[0]
		var keyword: String = written_as.strip_edges().trim_suffix("(").strip_edges()
		assert_true(
			written.contains("`%s`" % keyword),
			"the README says `%s` is refused" % keyword
		)


## And the scripts it says the palette is built from are the ones it is built
## from.
func test_the_readme_names_the_classes_the_palette_reads() -> void:
	var written: String = FileAccess.get_file_as_string(README)

	for declared: StringName in ComposerCatalog.SOURCES:
		assert_true(
			written.contains(String(declared)), "the README names %s" % declared
		)
