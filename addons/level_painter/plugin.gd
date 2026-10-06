@tool
extends EditorPlugin

## Registers the Level Painter as a bottom panel (like Output / Debugger). Toggle it
## from the bottom of the editor; it gives a wide canvas for painting maps.

const DockScript := preload("res://addons/level_painter/dock/level_painter_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = DockScript.new()
	_dock.name = "LevelPainter"
	add_control_to_bottom_panel(_dock, "Level Painter")


func _exit_tree() -> void:
	if _dock:
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null
