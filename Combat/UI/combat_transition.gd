class_name CombatTransition
extends CanvasLayer

## A short Persona-inspired intro wipe played when a fight begins. A diagonal
## curtain and a red accent slash sweep in to cover the screen, the words
## "MONSTERS!" (top) and "FIGHT!" (bottom) slam in, then everything sweeps off to
## reveal the ready battle.
##
## Usage: add to the tree and call play(). Await `covered` to build/begin combat
## behind the curtain; the node frees itself after `finished`.

signal covered    # screen fully hidden — safe to build/begin combat behind it
signal finished   # wipe complete, node about to free itself

# Combat UI is authored in the 1920x1080 base canvas (see combat_overlay.gd), so
# these absolute positions live in that same space.
const SCREEN := Vector2(1920, 1080)

const CURTAIN_COLOR := Color(0.06, 0.02, 0.03, 1.0)
const ACCENT_COLOR := Color(0.85, 0.12, 0.16, 1.0)

# Slide anchor positions. Each rect rotates about its own centre (pivot = size/2),
# so its cover position is screen-centre minus half its size.
const CURTAIN_COVER := Vector2(-540, -560)
const CURTAIN_OFF := Vector2(-540, 2040)     # continues down and off-screen
const ACCENT_COVER := Vector2(-540, 280)
const ACCENT_OFF := Vector2(2860, 280)       # continues right and off-screen

var _font: FontFile
var _root: Control
var _curtain: ColorRect
var _accent: ColorRect
var _top_label: Label
var _bottom_label: Label


func _ready() -> void:
	layer = 100   # above the combat overlay (40) and the HUD
	_font = load("res://Fonts/VeniceClassic.ttf")

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow input during the wipe
	add_child(_root)

	# Draw order: curtain (back), accent slash, then the text on top.
	_curtain = _make_rect(Vector2(3000, 2200), CURTAIN_COLOR)
	_curtain.position = CURTAIN_COVER + Vector2(0, -2600)   # start above the screen
	_root.add_child(_curtain)

	_accent = _make_rect(Vector2(3000, 520), ACCENT_COLOR)
	_accent.position = ACCENT_COVER + Vector2(-3400, 0)     # start off the left
	_root.add_child(_accent)

	_top_label = _make_label("MONSTERS!", 140, Color(0.93, 0.90, 0.86))
	_top_label.position = Vector2(-SCREEN.x, 150)           # start off the left
	_root.add_child(_top_label)

	_bottom_label = _make_label("FIGHT!", 180, ACCENT_COLOR.lightened(0.15))
	_bottom_label.position = Vector2(SCREEN.x, 720)         # start off the right
	_root.add_child(_bottom_label)


func play() -> void:
	# 1) Curtain + accent sweep in to cover the screen.
	var t := create_tween().set_parallel(true)
	t.tween_property(_curtain, "position", CURTAIN_COVER, 0.32) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(_accent, "position", ACCENT_COVER, 0.32) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await t.finished
	covered.emit()

	# 2) The two words slam in (a slight overshoot from BACK easing), then hold.
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(_top_label, "position:x", 0.0, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t2.tween_property(_bottom_label, "position:x", 0.0, 0.30) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t2.finished
	await get_tree().create_timer(0.45).timeout

	# 3) Everything sweeps off, revealing the battle built behind us.
	var t3 := create_tween().set_parallel(true)
	t3.tween_property(_curtain, "position", CURTAIN_OFF, 0.30) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t3.tween_property(_accent, "position", ACCENT_OFF, 0.30) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t3.tween_property(_top_label, "position:x", -SCREEN.x, 0.30)
	t3.tween_property(_bottom_label, "position:x", SCREEN.x, 0.30)
	await t3.finished

	finished.emit()
	queue_free()


# A big rect rotated about its centre, sized well past the screen so it still
# covers every corner at the diagonal angle.
func _make_rect(size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.size = size
	r.pivot_offset = size / 2.0
	r.rotation_degrees = -18.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# A full-width, centre-aligned banner label; sliding its x sweeps the word across.
func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.size = Vector2(SCREEN.x, 260)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	return l
