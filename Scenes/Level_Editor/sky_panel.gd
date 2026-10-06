extends PopupPanel
class_name LevelSkyPanel

## The Level Editor's Sky panel: switches a floor's sky on, picks a preset, and
## exposes every LevelSky setting as a slider or colour, with a live 3D preview.
## It edits a GridLevelData's `sky` dictionary in place and emits `changed`.

signal changed

const PREVIEW_SIZE := Vector2i(520, 300)
const LABEL_WIDTH := 130.0

var _data: GridLevelData
var _settings: Dictionary = {}
var _refreshing := false             # true while widgets are being written, not edited

var _enabled: CheckButton
var _link: CheckButton
var _presets: OptionButton
var _sliders: Dictionary = {}        # key -> HSlider
var _readouts: Dictionary = {}       # key -> Label
var _formats: Dictionary = {}        # key -> printf format
var _colors: Dictionary = {}         # key -> ColorPickerButton

# Preview: a small world of its own with a patch of ground and two wall blocks.
var _env: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D
var _material: ShaderMaterial
var _plain_note: Label


func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	margin.add_child(columns)

	# --- Left: preview and the big switches ---
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	left.add_child(_heading("Sky"))
	left.add_child(_build_preview())

	_enabled = CheckButton.new()
	_enabled.text = "This floor has a sky"
	_enabled.tooltip_text = "Off: the plain dark backdrop of an underground level."
	_enabled.toggled.connect(func(on): _edit("enabled", on))
	left.add_child(_enabled)

	var preset_row := HBoxContainer.new()
	left.add_child(preset_row)
	preset_row.add_child(_label("Preset"))
	_presets = OptionButton.new()
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset_name in LevelSky.PRESETS:
		_presets.add_item(preset_name)
	_presets.selected = -1
	_presets.item_selected.connect(_on_preset)
	preset_row.add_child(_presets)

	_link = CheckButton.new()
	_link.text = "Sun lights the level"
	_link.tooltip_text = "Aim the level's shadow-casting sunlight at the sun in the sky, in its colour and strength."
	_link.toggled.connect(func(on): _edit("link_sun", on))
	left.add_child(_link)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	left.add_child(buttons)
	var reset := Button.new()
	reset.text = "Reset"
	reset.tooltip_text = "Put every setting back to its starting value."
	reset.pressed.connect(_on_reset)
	buttons.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done.pressed.connect(hide)
	buttons.add_child(done)

	# --- Right: every setting ---
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(470, 620)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	for row in LevelSky.ROWS:
		if row.has("section"):
			rows.add_child(_heading(String(row["section"])))
		elif String(row.get("type", "")) == "color":
			_add_color(rows, row)
		else:
			_add_slider(rows, row)


## Open the panel on a floor's sky.
func open(data: GridLevelData) -> void:
	_data = data
	_settings = LevelSky.settings_for(data.sky)
	_presets.selected = -1
	_refresh_widgets()
	_refresh_preview()
	popup_centered()


#region Building
func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", UIStyle.GOLD)
	return l

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	return l

func _add_color(parent: Control, row: Dictionary) -> void:
	var key := String(row["key"])
	var line := HBoxContainer.new()
	parent.add_child(line)
	line.add_child(_label(String(row["label"])))
	var button := ColorPickerButton.new()
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.edit_alpha = false
	button.color_changed.connect(func(c): _edit(key, c))
	line.add_child(button)
	_colors[key] = button

func _add_slider(parent: Control, row: Dictionary) -> void:
	var key := String(row["key"])
	var line := HBoxContainer.new()
	parent.add_child(line)
	line.add_child(_label(String(row["label"])))
	var slider := HSlider.new()
	slider.min_value = float(row["min"])
	slider.max_value = float(row["max"])
	slider.step = float(row["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v): _edit(key, v))
	line.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(70, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(readout)
	_sliders[key] = slider
	_readouts[key] = readout
	_formats[key] = String(row.get("fmt", "%.2f"))

func _build_preview() -> Control:
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(PREVIEW_SIZE)
	frame.stretch = true
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(viewport)

	var world := WorldEnvironment.new()
	_env = Environment.new()
	world.environment = _env
	viewport.add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	viewport.add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 80.0
	viewport.add_child(_camera)

	# A patch of floor and two wall-sized blocks, so the light has something to land on.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	ground.material_override = _flat_material(Color(0.62, 0.55, 0.42))
	viewport.add_child(ground)
	for spot in [Vector3(-4.5, 1.5, -6.0), Vector3(5.0, 1.5, -9.0)]:
		var block := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2, 3, 2)
		block.mesh = box
		block.position = spot
		block.material_override = _flat_material(Color(0.36, 0.31, 0.26))
		viewport.add_child(block)

	_plain_note = Label.new()
	_plain_note.text = "No sky on this floor"
	_plain_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_plain_note.add_theme_color_override("font_color", UIStyle.MUTED)
	frame.add_child(_plain_note)
	return frame

func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m
#endregion


#region Editing
func _edit(key: String, value) -> void:
	if _refreshing or _data == null:
		return
	_settings[key] = value
	if value is float and _readouts.has(key):
		_readouts[key].text = _formats[key] % value
	_commit()

func _on_preset(index: int) -> void:
	_settings = LevelSky.with_preset(_settings, _presets.get_item_text(index))
	_refresh_widgets()
	_commit()

func _on_reset() -> void:
	var was_on: bool = _settings.get("enabled", false)
	_settings = LevelSky.defaults()
	_settings["enabled"] = was_on
	_presets.selected = -1
	_refresh_widgets()
	_commit()

func _commit() -> void:
	_data.sky = _settings.duplicate()
	_refresh_preview()
	changed.emit()

func _refresh_widgets() -> void:
	_refreshing = true
	_enabled.button_pressed = bool(_settings["enabled"])
	_link.button_pressed = bool(_settings["link_sun"])
	for key in _colors:
		_colors[key].color = _settings[key]
	for key in _sliders:
		var v := float(_settings[key])
		_sliders[key].set_value_no_signal(v)
		_readouts[key].text = _formats[key] % v
	_refreshing = false
#endregion


#region Preview
func _refresh_preview() -> void:
	var on := bool(_settings.get("enabled", false))
	_plain_note.visible = not on
	if not on:
		# What a built level without a sky looks like.
		_material = null
		_env.background_mode = Environment.BG_COLOR
		_env.background_color = Color(0.08, 0.08, 0.1)
		_env.sky = null
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_color = Color(0.5, 0.5, 0.55)
		_env.ambient_light_energy = 0.6
		_sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
		_sun.light_color = Color.WHITE
		_sun.light_energy = 1.0
	elif _material == null:
		_material = LevelSky.apply(_env, _sun, _settings)
	else:
		LevelSky.push(_material, _settings)
		LevelSky.aim_sun(_sun, _settings)
	# Look a little to one side of the sun, so the disc and the lit clouds are in view.
	var toward := LevelSky.sun_vector(_settings)
	var heading := atan2(-toward.x, -toward.z) + deg_to_rad(28.0)
	_camera.position = Vector3(0, 0.7, 0)
	_camera.rotation = Vector3(deg_to_rad(16.0), heading, 0)
#endregion
