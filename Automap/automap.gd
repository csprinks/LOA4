extends CanvasLayer
class_name Automap

## Automap HUD: a child of the player, so it rides level transitions. Shows an
## always-on minimap in the top-left corner; "toggle_automap" (M) or the corner
## button grows that same panel into a large centred map (animated) of everything
## explored on this level. The map itself is drawn by AutomapView.

const MINI_SIZE := 200.0             # minimap square, px
const MINI_MARGIN := 14.0            # gap from the screen's top-left corner
const LARGE_FRACTION := 0.88         # enlarged square, as a fraction of the short screen side
const EXPAND_TIME := 0.35
const DIM_ALPHA := 0.6               # backdrop darkening behind the enlarged map
const FRAME_INSET := 3.0             # map inset inside the panel's gold border
const TOGGLE_SIZE := 28.0

var _dim: ColorRect
var _panel: Panel
var _view: AutomapView
var _toggle: Button
var _expanded := false
var _expand := 0.0                   # 0 = minimap, 1 = enlarged (tweened)
var _tween: Tween

func _ready() -> void:
	layer = 40
	_build_ui()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_automap"):
		toggle_expanded()

# Grow the minimap into the large map, or shrink it back.
func toggle_expanded() -> void:
	_expanded = not _expanded
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_expand, _expand, 1.0 if _expanded else 0.0, EXPAND_TIME)
	_toggle.queue_redraw()

# Lay everything out for an expand amount of 0 (minimap) .. 1 (enlarged).
func _set_expand(v: float) -> void:
	_expand = v
	var screen := get_viewport().get_visible_rect().size
	var side := minf(screen.x, screen.y) * LARGE_FRACTION
	var mini_pos := Vector2(MINI_MARGIN, MINI_MARGIN)
	var large_pos := (screen - Vector2(side, side)) * 0.5
	_panel.position = mini_pos.lerp(large_pos, v)
	_panel.size = Vector2(MINI_SIZE, MINI_SIZE).lerp(Vector2(side, side), v)
	_dim.color.a = DIM_ALPHA * v
	_view.large_size = Vector2.ONE * (side - FRAME_INSET * 2.0)
	_view.expand = v

func _build_ui() -> void:
	# Backdrop that darkens the game behind the enlarged map.
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	# One panel serves as both minimap and large map; _set_expand() moves and
	# resizes it. Same dark-brown fill + gold border as the rest of the HUD.
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UIStyle.frame(UIStyle.GOLD, 2, 6))
	add_child(_panel)

	_view = AutomapView.new()
	_panel.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(FRAME_INSET))

	# Inner hairline + rim drawn over the map so its square corners stay tucked
	# under the rounded frame.
	var hairline := Panel.new()
	hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hairline.add_theme_stylebox_override("panel", UIStyle.outline(UIStyle.GOLD_DIM, 1, 3))
	_panel.add_child(hairline)
	hairline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, int(FRAME_INSET))

	var rim := Panel.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.add_theme_stylebox_override("panel", UIStyle.outline(UIStyle.GOLD, 2, 6))
	_panel.add_child(rim)
	rim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Enlarge / shrink button, pinned to the panel's bottom-right corner.
	_toggle = Button.new()
	_toggle.focus_mode = Control.FOCUS_NONE   # never steals Space/Enter from the game
	_toggle.tooltip_text = "Toggle map (M)"
	_toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_toggle.add_theme_stylebox_override("normal", UIStyle.frame(UIStyle.GOLD_DIM, 1, 4))
	_toggle.add_theme_stylebox_override("hover", UIStyle.frame(UIStyle.GOLD_BRIGHT, 1, 4))
	_toggle.add_theme_stylebox_override("pressed", UIStyle.frame(UIStyle.GOLD_BRIGHT, 1, 4, UIStyle.INSET_BG))
	_toggle.pressed.connect(toggle_expanded)
	_toggle.draw.connect(_draw_toggle_icon)
	_panel.add_child(_toggle)
	_toggle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var pad := FRAME_INSET + 4.0
	_toggle.offset_left = -TOGGLE_SIZE - pad
	_toggle.offset_top = -TOGGLE_SIZE - pad
	_toggle.offset_right = -pad
	_toggle.offset_bottom = -pad

	_set_expand(0.0)
	get_viewport().size_changed.connect(func(): _set_expand(_expand))

# Corner brackets: pointing outward to enlarge, inward to shrink.
func _draw_toggle_icon() -> void:
	var c := _toggle.size * 0.5
	var leg := TOGGLE_SIZE * 0.16
	var reach := TOGGLE_SIZE * (0.12 if _expanded else 0.27)
	var inward := 1.0 if _expanded else -1.0
	var col := UIStyle.GOLD_BRIGHT if _toggle.is_hovered() else UIStyle.GOLD
	for d: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var corner := c + d * reach
		_toggle.draw_polyline(PackedVector2Array([
			corner + Vector2(d.x * inward * leg, 0.0), corner,
			corner + Vector2(0.0, d.y * inward * leg)]), col, 2.0, true)
