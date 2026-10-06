class_name UIStyle
extends RefCounted

## Shared palette + small StyleBox builders for UI that is built in code (combat
## overlay, HUD highlights, text box). Scene-authored UI gets the same look from
## res://UI/game_theme.tres; keep the two in step when retuning colours.

const FONT_PATH := "res://Fonts/KingthingsFoundation.ttf"

const GOLD := Color(0.914, 0.784, 0.467)          # frame / heading gold
const GOLD_BRIGHT := Color(1.0, 0.925, 0.66)      # highlights, active turn
const GOLD_DIM := Color(0.49, 0.36, 0.15)         # hairlines, inactive borders
const CREAM := Color(0.93, 0.87, 0.74)            # body text
const MUTED := Color(0.68, 0.61, 0.48)            # secondary text
const PANEL_BG := Color(0.07, 0.05, 0.035, 0.94)  # near-black warm brown
const INSET_BG := Color(0.03, 0.02, 0.015, 0.85)  # wells (bars, log, slots)
const OUTLINE := Color(0.05, 0.03, 0.02)          # text outline

const HP_RED := Color(0.78, 0.16, 0.13)
const AP_GREEN := Color(0.33, 0.68, 0.22)


static func font() -> FontFile:
	return load(FONT_PATH)


# A dark panel with a gold border, for code-built frames that need a per-instance
# border colour (enemy cards, turn chips, highlights).
static func frame(border: Color = GOLD, width: int = 2, radius: int = 8, bg: Color = PANEL_BG) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(width)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb


# Border only (no fill): overlays such as the active-hero highlight.
static func outline(border: Color = GOLD_BRIGHT, width: int = 3, radius: int = 9) -> StyleBoxFlat:
	var sb := frame(border, width, radius)
	sb.draw_center = false
	return sb
