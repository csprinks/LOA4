extends CanvasLayer

## Full-screen fade-to-black overlay, driven by tweens. Self-contained; used for
## scene transitions and (later) level loads.

const FADE_DURATION = 0.4

var fade_overlay: ColorRect
var is_fading = false

func _ready():
	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.anchor_right = 1.0
	fade_overlay.anchor_bottom = 1.0
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.color = Color(0, 0, 0, 0)  # Start transparent
	fade_overlay.z_index = 1000  # Always on top
	add_child(fade_overlay)

# Fade to black.
func fade_out(duration: float = FADE_DURATION) -> void:
	if is_fading:
		return

	is_fading = true
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(fade_overlay, "color", Color(0, 0, 0, 1), duration)
	await tween.finished
	is_fading = false

# Fade from black back to clear.
func fade_in(duration: float = FADE_DURATION) -> void:
	if is_fading:
		return

	is_fading = true
	fade_overlay.color = Color(0, 0, 0, 1)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(fade_overlay, "color", Color(0, 0, 0, 0), duration)
	await tween.finished
	is_fading = false

# Fade out, swap scenes, fade back in.
func transition_to_scene(scene_path: String, fade_duration: float = FADE_DURATION) -> void:
	await fade_out(fade_duration)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().create_timer(0.1).timeout  # Let the new scene initialize
	await fade_in(fade_duration)
