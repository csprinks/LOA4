class_name StatBar
extends Control

## A horizontal bar whose fill is drawn by the animated-stripes shader. The fill
## width tracks a 0-1 ratio; stripe/gap colours are set per instance (red for HP,
## green for AP). Used by CharacterCard in place of a plain ProgressBar.

@export var stripe_color: Color = Color(0.85, 0.15, 0.15, 1.0):
	set(value):
		stripe_color = value
		_apply_colors()
@export var gap_color: Color = Color(0.12, 0.0, 0.0, 0.35):
	set(value):
		gap_color = value
		_apply_colors()

@onready var _fill: ColorRect = %Fill

var _ratio: float = 1.0

func _ready() -> void:
	# Give this instance its own material so per-bar colours don't clobber the
	# shared scene material.
	if _fill and _fill.material is ShaderMaterial:
		_fill.material = _fill.material.duplicate()
	_apply_colors()
	set_ratio(_ratio)

func set_ratio(r: float) -> void:
	_ratio = clampf(r, 0.0, 1.0)
	if _fill:
		_fill.anchor_right = _ratio

func _apply_colors() -> void:
	if _fill and _fill.material is ShaderMaterial:
		_fill.material.set_shader_parameter("color_stripe", stripe_color)
		_fill.material.set_shader_parameter("color_gap", gap_color)
