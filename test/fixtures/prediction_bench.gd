## A journal, the character a guess is unwound against, and the guess itself.
##
## Four lines each time, in two suites, and the fourth is the one that is easy
## to leave out: a component still processing moves things between the line that
## sets a guess up and the line that reads what became of it.
##
## The attributes are handed in rather than fixed here, because what a guess
## spends is the suite's business and a bench that decided it would be a bench
## every new suite has to work around.
##
## @meta_license: GAS_Engine Community Use License 1.0
class_name PredictionBench extends RefCounted

const Fixture = preload("res://test/fixtures/asc_fixture.gd")

var journal: GameplayPredictionJournal = null
var fixture: ASCFixture = null

## One guess, already minted. Most tests need exactly one and the ones that
## need two mint the second themselves.
var key: GameplayPredictionKey = null


static func stand(
	host: GutTest, peer: int, attributes: Dictionary[StringName, float] = {}
) -> PredictionBench:
	var bench: PredictionBench = PredictionBench.new()
	bench.journal = GameplayPredictionJournal.new()
	bench.fixture = Fixture.create("Predictor")
	host.add_child_autofree(bench.fixture.owner)
	bench.fixture.asc.set_process(false)
	for name: StringName in attributes:
		bench.fixture.set_base(name, attributes[name])
	bench.key = bench.journal.next_key(peer)
	return bench


func asc() -> AbilitySystemComponent:
	return fixture.asc


## Let go of what was written down. The character is the host's to free.
func dispose() -> void:
	journal.clear()
