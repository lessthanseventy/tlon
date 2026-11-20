extends RefCounted

# Gridwright Round, a chunky pixel font, for the sidebar's view title alone. Everything else keeps
# the default font (BODY, SMALL, LABEL below): at the sizes the house
# reads in (14-17 px) the pack's text fonts are a size short of their design size or wider than
# the room's cards allow, and long lines turn to mush. Round is drawn at its design size (16 px)
# or a whole multiple of it, whatever size is asked (`fixed_size`), with no smoothing, so it stays
# sharp; a character it lacks (a thing's text in another script, an emoji) falls back to the
# default font. A Label takes it through the `HEADING` theme variation, so a change of the
# setting applies at once.
const Looks := preload("res://looks.gd")
const HEADING := "Heading"
const FILE := "pixel-fonts-2/Gridwright Pixel Fonts 2/TTF/Gridwright-Round.ttf"
const DESIGN_SIZE := 16
# The sidebar's one scale: the pixel face for the view title only, the body face at three sizes.
const TITLE := 22
const BODY := 15
const SMALL := 13
const LABEL := 12

static var _pixel: FontFile


static func files() -> Array:
	return [FILE]


# the heading font: Round when the look is on and the file is there, else the default font
static func heading() -> Font:
	if not Looks.on("font") or not FileAccess.file_exists(Looks.art_dir.path_join(FILE)):
		return ThemeDB.fallback_font
	if _pixel == null:
		var f := FontFile.new()
		f.load_dynamic_font(Looks.art_dir.path_join(FILE))
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.hinting = TextServer.HINTING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		f.fixed_size = DESIGN_SIZE
		f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
		f.fallbacks = [ThemeDB.fallback_font]
		_pixel = f
	return _pixel


static func apply() -> void:
	var theme := ThemeDB.get_default_theme()
	theme.set_type_variation(HEADING, "Label")
	theme.set_font("font", HEADING, heading())
