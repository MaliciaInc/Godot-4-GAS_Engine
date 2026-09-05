## Every colour, measure and surface the Composer draws with, declared once.
##
## A design token repeated at the point of use is a design that drifts: the
## third card written gets a slightly different grey, and nobody notices until
## the screen looks subtly wrong for reasons no one can name. Everything visual
## reads from here.
##
## Colours are built from bytes rather than hex strings on purpose. A hex string
## is a literal the tooling has to scan and a human has to trust; `Color8` says
## the same thing in numbers that cannot be mistyped into a valid-but-wrong
## colour.
##
## @meta_addon: GAS_Engine
## @meta_license: GAS_Engine Community Use License 1.0
class_name ComposerTheme extends RefCounted

#region Palette
## The chrome that frames the graph. The canvas itself is GraphEdit's own
## surface now, so this is the only ground the Composer still paints.
const CHROME: Color = Color(0.055, 0.055, 0.075)

const ROW: Color = Color(0.118, 0.118, 0.149)
const RULE: Color = Color(0.125, 0.125, 0.165)

const TEXT: Color = Color(0.929, 0.929, 0.949)
const TEXT_DIM: Color = Color(0.541, 0.541, 0.600)
const TEXT_FAINT: Color = Color(0.353, 0.353, 0.408)

## The one accent, spent sparingly: the active view and the primary control.
## Anything else stays grey. It also lit a glow under each card and a bead on
## each wire, and both of those went with the hand-drawn surface that painted
## them.
const ACCENT: Color = Color(0.482, 0.361, 1.0)

const WARNING: Color = Color(0.851, 0.643, 0.255)
const ERROR: Color = Color(0.878, 0.322, 0.322)

## What a pin carries, by colour.
##
## Semantic rather than decorative: two pins of the same family look the same in
## every ability somebody opens, so the shape of a graph can be read before any
## of its words are. Chosen against this canvas, not taken from anyone else's
## editor. Which type belongs to which family is `ComposerPortTypes`' business;
## what each family looks like is the palette's, and it lives here so it can be
## seen beside the surface it has to sit on.
const PORT_EXECUTION: Color = Color(0.898, 0.906, 0.941)
const PORT_BOOL: Color = Color(0.878, 0.322, 0.322)
const PORT_INT: Color = Color(0.208, 0.788, 0.804)
const PORT_FLOAT: Color = Color(0.400, 0.851, 0.510)
const PORT_TEXT: Color = Color(0.902, 0.396, 0.808)
const PORT_PATH: Color = Color(0.588, 0.278, 0.549)
const PORT_VECTOR: Color = Color(0.933, 0.812, 0.353)
const PORT_COLOUR: Color = Color(0.847, 0.859, 0.878)
const PORT_OBJECT: Color = Color(0.361, 0.573, 0.965)
const PORT_UNTYPED: Color = Color(0.541, 0.541, 0.600)

const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.5)
const HAIRLINE: Color = Color(1.0, 1.0, 1.0, 0.035)
const TRANSPARENT: Color = Color(0.0, 0.0, 0.0, 0.0)
#endregion


#region Owning the look
## The types a Godot widget draws its own chrome out of.
##
## GraphEdit brings a zoom row, a grid toggle and a snap box of its own, and
## every one of them is an ordinary Button, Label or SpinBox that reads its font
## off whatever theme it is standing in.
## The theme type a Label resolves its own font against. Named once: a card
## says it about the label GraphNode draws its title in, and the chrome theme
## says it about every other label a widget builds for itself.
const LABEL_TYPE: StringName = &"Label"

const CHROME_TYPES: Array[StringName] = [
	&"Button",
	&"CheckBox",
	&"CheckButton",
	LABEL_TYPE,
	&"LineEdit",
	&"OptionButton",
	&"SpinBox",
]


## A theme that says how big the text on a widget's own chrome is.
##
## Needed because a default size is only a floor: the lookup walks the chain by
## type, so a project theme naming Button outright still beats a default set
## nearer the control. Standing in a game whose theme says 96, GraphEdit's zoom
## row grew to cover the first cards in the graph and swallowed every click on
## them - the Composer was unusable in the one place it had to work, and looked
## right in the editor because the editor's theme is quiet.
static func own_chrome() -> Theme:
	var own: Theme = Theme.new()
	own.default_font_size = FONT_VALUE
	for kind: StringName in CHROME_TYPES:
		own.set_font_size(GASEditorTheme.FONT_SIZE, kind, FONT_VALUE)
	return own
#endregion


#region Measures
## One scale. Every gap is a multiple of it, so nothing lands on a number
## someone picked because it looked right that day.
const S1: float = 4.0
const S2: float = 8.0
const S3: float = 12.0
const S4: float = 20.0
const S5: float = 28.0

const FONT_TITLE: int = 14
const FONT_VALUE: int = 12
const FONT_LABEL: int = 10

## Fixed. Anything that does not fit goes to the Inspector rather than making
## one card wider than its neighbours.
## A card is as wide as the longest thing it has to say, between these.
##
## The minimum keeps a graph of short nodes from looking ragged. The maximum is
## where a card stops growing and starts truncating instead, because one node
## carrying a long resource path should not push the whole column across the
## canvas.
const NODE_MIN_WIDTH: float = 232.0

## What an unmeasured card counts as while it has no height yet.
const NODE_MIN_HEIGHT: float = 106.0
const PAD_X: float = 14.0
const PAD_Y: float = 12.0

const RADIUS_ROW: int = 8

## Grid spacing at 1.0 zoom. The dots keep their size at every level and the
## mesh changes pitch instead, so pulling out never turns them into smudges.

## The space between one column of cards and the next. A step no longer works:
## columns are as wide as their widest card, so what is fixed is the gap.
const COLUMN_GAP: float = 88.0

## The space between one lane of cards and the next, for the reason COLUMN_GAP
## is a gap: a lane is as tall as its tallest card. A fixed step of 210 put a
## three-field card, which is 230 tall, twenty pixels into the lane below it.
const LANE_GAP: float = 88.0

## An ellipse rather than a circle, at this multiple of the card it belongs to.
## A circle around a short wide card spills far above and below it.
## The wash left over the graph while a selection box is being dragged. Faint
## on purpose: it says which cards it covers without hiding them.

## How thick the outline around a picked card is.


#endregion


#region Surfaces
## The card, the field row, the floating panel - all the same builder, because
## they differ only in fill, radius and whether they cast a shadow.
static func box(
	fill: Color, radius: int, border: Color, shadow: int = 0
) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(1)
	style.shadow_color = SHADOW
	style.shadow_size = shadow
	style.shadow_offset = Vector2(0.0, 7.0)
	style.content_margin_left = PAD_X
	style.content_margin_right = PAD_X
	style.content_margin_top = PAD_Y
	style.content_margin_bottom = PAD_Y + 1.0
	return style


## A value slot inside a card: tighter margins, no shadow, a hairline edge.
static func field_box() -> StyleBoxFlat:
	var style: StyleBoxFlat = box(ROW, RADIUS_ROW, HAIRLINE)
	style.content_margin_top = S2
	style.content_margin_bottom = S2
	style.content_margin_left = S3 - 1.0
	style.content_margin_right = S3 - 1.0
	return style


## A filled circle, for the core of a port bead and the dot on a card's title.
static func disc(fill: Color, radius: float) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(ceili(radius))
	return style
#endregion


#region Diagnostics
## How a severity looks, as two tables rather than two match statements.
##
## Indexed by the enum, so the order here IS ComposerGraph.Severity's order and
## a severity added without a colour or a mark is a missing entry rather than a
## silent fall-through to whatever the default branch happened to be. A test
## holds the two lengths against the enum.
##
## Two branching functions were the alternative, and they were the same shape
## twice - which is how a card's dot and its Output row end up disagreeing about
## one fact.
## A file this tool cannot draw is not a file with mistakes in it, so it is not
## red - but it is something a person has to know, so it is not grey either. Grey
## is what a count of nodes is drawn in, and a reason that reads as a count is a
## reason nobody reads. Hollow rather than solid, for the same reason: it has to
## be told apart from an error at a glance.
const SEVERITY_COLORS: Array[Color] = [TEXT_FAINT, WARNING, ERROR, WARNING]
const SEVERITY_MARKS: Array[String] = ["•", "▲", "■", "□"]


static func severity_color(severity: ComposerGraph.Severity) -> Color:
	return SEVERITY_COLORS[int(severity)]


## The glyph that opens an Output row. Same table, same order.
static func severity_mark(severity: ComposerGraph.Severity) -> String:
	return SEVERITY_MARKS[int(severity)]
#endregion
