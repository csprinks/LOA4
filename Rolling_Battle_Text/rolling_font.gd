extends Control
class_name RollingNumbers

# --- Configuration ---
@export var font_size: int = 32
@export var font: FontFile                          # Custom font choice
@export var digit_colors: Array[Color] = [Color.WHITE]
@export var digit_spacing: float = 0.0
@export var roll_delay: float = 0.1                  # Delay between digit reveals
@export var display_time: float = 1.0                # Time to show full number
@export var outline_size: int = 2
@export var outline_color: Color = Color.BLACK
@export var bottom_margin: int = 20
@export var bounce_height: float = 20.0
@export var bounce_duration: float = 0.5
@export var bounce_count: int = 2
@export var bounce_decay: float = 0.5
@export var debug: bool = false

enum State { ROLLING, DISPLAYING, FINISHED }

var texture_rect: TextureRect
@onready var fallback_font: Font = ThemeDB.fallback_font

var _effects: Array = []

# --- Public API ---

## Spawn a rolling number effect (e.g. damage/heal amount) over this control.
func spawn(number: int) -> void:
	_effects.append(_make_effect(number))


# --- Lifecycle ---

func _ready() -> void:
	texture_rect = get_node_or_null("TextureRect")
	if texture_rect:
		texture_rect.gui_input.connect(_on_texture_rect_gui_input)
		texture_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	call_deferred("_update_size")


func _update_size() -> void:
	if texture_rect:
		size = texture_rect.size


func _on_texture_rect_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spawn(randi_range(100, 1000))


func _process(delta: float) -> void:
	var needs_redraw := false

	for effect in _effects:
		effect.timer += delta
		needs_redraw = _update_bounces(effect, delta) or needs_redraw
		needs_redraw = _update_state(effect) or needs_redraw

	var prev_count := _effects.size()
	_effects = _effects.filter(func(e): return e.state != State.FINISHED)
	needs_redraw = needs_redraw or _effects.size() != prev_count

	if needs_redraw:
		queue_redraw()


# --- Effect / bounce helpers ---

func _make_effect(number: int) -> Dictionary:
	return {
		"number": str(number),
		"current_index": 0,
		"timer": 0.0,
		"state": State.ROLLING,
		"bounce_data": [],
	}


func _make_bounce() -> Dictionary:
	return {
		"current_bounce": 0,
		"timer": 0.0,
		"offset": 0.0,
		"current_height": bounce_height,
	}


func _update_bounces(effect: Dictionary, delta: float) -> bool:
	var changed := false
	for bounce in effect.bounce_data:
		if bounce.current_bounce >= bounce_count:
			continue

		bounce.timer += delta
		var progress: float = bounce.timer / bounce_duration

		if progress > 1.0:
			bounce.current_bounce += 1
			bounce.timer = 0.0
			progress = 0.0
			bounce.current_height *= bounce_decay

		if bounce.current_bounce < bounce_count:
			bounce.offset = -bounce.current_height * sin(progress * PI)
			changed = true

	return changed


func _update_state(effect: Dictionary) -> bool:
	match effect.state:
		State.ROLLING:
			if effect.timer < roll_delay:
				return false
			effect.timer = 0.0
			effect.current_index += 1
			effect.bounce_data.append(_make_bounce())
			if effect.current_index >= effect.number.length():
				effect.state = State.DISPLAYING
			return true

		State.DISPLAYING:
			if effect.timer < display_time:
				return false
			effect.state = State.FINISHED
			return true

	return false


# --- Drawing ---

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return

	var content_scale: float = get_tree().root.content_scale_factor
	var font_size_adjusted: float = font_size * content_scale
	var scaled_spacing: float = digit_spacing * content_scale
	var draw_font: Font = font if font != null else fallback_font
	if draw_font == null:
		return

	var base_position := Vector2(
		size.x / 2,
		size.y - bottom_margin - (font_size_adjusted / 2)
	)

	if debug:
		_draw_debug_crosshair(base_position, draw_font, font_size_adjusted)

	for effect in _effects:
		_draw_effect(effect, draw_font, base_position, font_size_adjusted, scaled_spacing)


func _text_width(font_res: Font, text: String, font_size_px: float, spacing: float) -> float:
	var width := 0.0
	for i in text.length():
		width += font_res.get_char_size(text[i].unicode_at(0), font_size_px).x
		if i < text.length() - 1:
			width += spacing
	return width


func _draw_effect(effect: Dictionary, draw_font: Font, base_position: Vector2, font_size_adjusted: float, scaled_spacing: float) -> void:
	var display_text: String = effect.number.substr(0, effect.current_index + 1)
	var total_width := _text_width(draw_font, display_text, font_size_adjusted, scaled_spacing)
	var draw_pos := base_position - Vector2(total_width / 2, 0)

	var current_x := draw_pos.x
	for i in display_text.length():
		var character := display_text[i]
		var char_size := draw_font.get_char_size(character.unicode_at(0), font_size_adjusted)

		var char_offset := Vector2.ZERO
		if i < effect.bounce_data.size():
			char_offset.y = effect.bounce_data[i].offset

		var char_pos := Vector2(current_x, draw_pos.y) + char_offset
		var digit_color: Color = digit_colors[i % digit_colors.size()] if digit_colors.size() > 0 else Color.WHITE

		draw_string_outline(draw_font, char_pos, character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_adjusted, outline_size, outline_color)
		draw_string(draw_font, char_pos, character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_adjusted, digit_color)

		current_x += char_size.x + scaled_spacing

	if debug:
		var pos_text := "Pos: %s Width: %s" % [draw_pos, total_width]
		draw_string(draw_font, Vector2(10, 50), pos_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_adjusted * 0.7, Color.YELLOW)


func _draw_debug_crosshair(base_position: Vector2, draw_font: Font, font_size_adjusted: float) -> void:
	draw_line(base_position - Vector2(10, 0), base_position + Vector2(10, 0), Color.RED, 2)
	draw_line(base_position - Vector2(0, 10), base_position + Vector2(0, 10), Color.RED, 2)

	var debug_text := "Text Position: %s" % base_position
	draw_string(draw_font, Vector2(10, 20), debug_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_adjusted, Color.YELLOW)

	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0, 0, 0.3), false, 2.0)
