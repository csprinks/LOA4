extends Control

## The in-game Level Editor: where the game's modules are made.
##
## Two screens in one scene:
##   MODULES  pick, create, play or delete a module, and choose which one a New
##            Game starts in.
##   EDITOR   paint a module's floors — floor, walls & doors, floor and wall
##            textures, ceilings, objects, each floor's sky, the start point and the links between triggers and what
##            they work — then Test Play it. "Back to Level Editor" (F10) returns here.
##
## It is a friendlier front end over the same core the editor dock uses
## (addons/level_painter): the paint canvas, GridLevelData, the build pipeline,
## floor connections, painted links and validation. Storage is ModuleLibrary.

const CanvasScript := preload("res://addons/level_painter/dock/level_paint_canvas.gd")
const SkyPanelScript := preload("res://Scenes/Level_Editor/sky_panel.gd")
const GAME_THEME := preload("res://UI/game_theme.tres")
const MENU_SCENE := "res://Scenes/Main_Menu/main_menu.tscn"

const LAYER_FLOOR := 0
const LAYER_EDGE := 1
const LAYER_OBJECT := 2
const LAYER_SPAWN := 3
const LAYER_LINK := 4
const LAYER_TEXTURE := 5
const LAYER_FLOOR_TEXTURE := 6
const LAYER_CEILING := 7

# Layer buttons, two to a row: [canvas layer, button text, hint shown under them].
const LAYERS := [
	[LAYER_FLOOR, "Floor", "Drag to paint floor; right-drag erases. The Room tool draws a walled room in one drag. A Pit is floor you can fall into."],
	[LAYER_EDGE, "Walls & Doors", "Click the line between two cells to put a wall or door there. Right-click removes it. Click a door to set where it leads."],
	[LAYER_FLOOR_TEXTURE, "Floor Textures", "Pick a texture, then click or drag over floor to paint it. Right-click puts floor back to plain. Pits can be textured too."],
	[LAYER_TEXTURE, "Wall Textures", "Pick a texture, then click or drag along walls to paint them. Right-click puts a wall back to plain. Doors set in a wall take the texture too."],
	[LAYER_CEILING, "Ceilings", "Pick a texture (or Plain), then click or drag over floor to roof it. Right-click opens it to the sky again. Roofed rooms are dark under a sky."],
	[LAYER_OBJECT, "Objects", "Click a cell to place the chosen object. Click an object that is already there to select and edit it. A Pit Trap drops the party to another floor."],
	[LAYER_SPAWN, "Start Point", "Click the cell where the party starts on this floor. Facing sets which way they look."],
	[LAYER_LINK, "Links", "Drag from a lever, pressure plate, wall lock or lever puzzle onto the door or platform it works. Drag the same pair again to unlink; right-click clears."],
]
const TOOLS := ["Brush", "Rectangle", "Room", "Fill"]
const FACINGS := ["North", "East", "South", "West"]

var _catalog: TileCatalog
var _module_id := ""
var _dungeon: DungeonData
var _active := 0
var _data: GridLevelData
var _dirty := false

# Modules screen
var _browser: Control
var _module_rows: Array = []
var _module_list: ItemList
var _module_info: Label
var _new_name: LineEdit
var _browser_status: Label
var _module_buttons: Array[Button] = []
var _campaign_button: Button

# Editor screen
var _editor: Control
var _canvas
var _name_edit: LineEdit
var _floor_opt: OptionButton
var _floor_name: LineEdit
var _hint: Label
var _tool_box: Control
var _facing_box: Control
var _palette_label: Label
var _palette: ItemList
var _palette_tiles: Array = []
var _palette_textures: Array = []   # WallTextures names, row for row, on the Wall Textures layer
var _texture_box: Control
var _texture_all_button: Button
var _ceiling_clear_button: Button
var _layer_buttons: Array[Button] = []
var _w_spin: SpinBox
var _blueprint_toggle: CheckButton
var _h_spin: SpinBox
var _props: VBoxContainer
var _problems: Array = []
var _problems_title: Label
var _problems_list: ItemList
var _status: Label
var _sel := { "type": "none" }

# Shared popups
var _confirm: ConfirmationDialog
var _confirm_action := Callable()
var _picker: PopupPanel
var _picker_list: ItemList
var _picker_param := ""
var _scene_dialog: FileDialog
var _scene_param := ""
var _scene_edit: LineEdit
var _sky_panel: LevelSkyPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The game theme at a size that suits a dense tool rather than a title screen.
	var editor_theme: Theme = GAME_THEME.duplicate()
	editor_theme.default_font_size = 20
	theme = editor_theme

	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.04, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_catalog = ModuleLibrary.catalog()
	_build_browser()
	_build_editor()
	_build_popups()

	var reopen := GameState.editor_open_module
	GameState.editor_open_module = ""
	GameState.editor_test_module = ""
	if reopen != "" and ModuleLibrary.exists(reopen):
		_open_module(reopen)
	else:
		_show_browser()


func _unhandled_key_input(event: InputEvent) -> void:
	if _editor.visible and event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed and event.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()


#region Small UI builders
func _btn(text: String, on_pressed: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_pressed)
	return b

func _lbl(text: String, size := 0, color := Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color != Color.TRANSPARENT:
		l.add_theme_color_override("font_color", color)
	return l

func _heading(text: String) -> Label:
	return _lbl(text, 24, UIStyle.GOLD)

func _panel(min_size: Vector2) -> Array:
	# A framed panel with comfortable padding; returns [panel, inner VBox].
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return [panel, box]

func _toggle(text: String, group: ButtonGroup, on_pressed: Callable, tip := "") -> Button:
	var b := _btn(text, on_pressed, tip)
	b.toggle_mode = true
	b.button_group = group
	return b
#endregion


#region Modules screen
func _build_browser() -> void:
	_browser = CenterContainer.new()
	_browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_browser)
	var made := _panel(Vector2(980, 780))
	_browser.add_child(made[0])
	var box: VBoxContainer = made[1]

	var title := _lbl("Level Editor", 48, UIStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _lbl("A module is one adventure: its floors, with their doors, treasure, puzzles and fights.", 18, UIStyle.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	_module_list = ItemList.new()
	_module_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_module_list.custom_minimum_size = Vector2(0, 340)
	_module_list.item_selected.connect(func(_i): _refresh_module_buttons())
	_module_list.item_activated.connect(func(_i): _on_open_pressed())
	box.add_child(_module_list)

	_module_info = _lbl("", 18, UIStyle.MUTED)
	_module_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_module_info)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var open := _btn("Edit", _on_open_pressed, "Open the selected module in the editor.")
	var play := _btn("▶ Play", _on_play_pressed, "Build the selected module and play it from its first floor.")
	_campaign_button = _btn("Use for New Game", _on_campaign_pressed,
		"Make the selected module the one a New Game starts in.")
	var delete := _btn("Delete", _on_delete_pressed, "Delete the selected module for good.")
	_module_buttons = [open, play, _campaign_button, delete]
	for b in _module_buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)

	box.add_child(HSeparator.new())
	var new_row := HBoxContainer.new()
	new_row.add_theme_constant_override("separation", 10)
	box.add_child(new_row)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "Name for a new module"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_name.text_submitted.connect(func(_t): _on_create_pressed())
	new_row.add_child(_new_name)
	new_row.add_child(_btn("Create Module", _on_create_pressed))

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	bottom.add_child(_btn("◀ Main Menu", _on_main_menu_pressed))
	_browser_status = _lbl("", 18, UIStyle.GOLD_BRIGHT)
	_browser_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_browser_status)

func _show_browser() -> void:
	_editor.visible = false
	_browser.visible = true
	_refresh_modules()

func _refresh_modules(select_id := "") -> void:
	_module_rows = ModuleLibrary.list_modules()
	_module_list.clear()
	for m in _module_rows:
		var text := "%s   —   %d floor%s" % [m.name, m.floors, "" if m.floors == 1 else "s"]
		if m.campaign:
			text += "   ★ New Game starts here"
		if not m.built:
			text += "   (not built yet)"
		_module_list.add_item(text)
		if m.id == select_id:
			_module_list.select(_module_list.item_count - 1)
	if _module_rows.is_empty():
		_browser_status.text = "No modules yet. Type a name below and press Create Module."
	_refresh_module_buttons()

func _selected_module() -> Dictionary:
	var picked := _module_list.get_selected_items()
	return _module_rows[picked[0]] if picked.size() > 0 and picked[0] < _module_rows.size() else {}

func _refresh_module_buttons() -> void:
	var m := _selected_module()
	for b in _module_buttons:
		b.disabled = m.is_empty()
	_module_info.text = "" if m.is_empty() else (m.description if m.description != "" else "No description.")
	_campaign_button.text = "Stop using for New Game" if m.get("campaign", false) else "Use for New Game"

func _on_create_pressed() -> void:
	var id := ModuleLibrary.create_module(_new_name.text)
	if id == "":
		_browser_status.text = "Could not create the module (check the Output log)."
		return
	_new_name.text = ""
	_open_module(id)

func _on_open_pressed() -> void:
	var m := _selected_module()
	if not m.is_empty():
		_open_module(m.id)

func _on_play_pressed() -> void:
	var m := _selected_module()
	if m.is_empty():
		return
	var dungeon := ModuleLibrary.load_module(m.id)
	_browser_status.text = _build_and_launch(m.id, dungeon)

func _on_campaign_pressed() -> void:
	var m := _selected_module()
	if m.is_empty():
		return
	ModuleLibrary.set_campaign("" if m.campaign else m.id)
	_browser_status.text = ("New Game no longer starts in a module (it uses the Showcase level)." if m.campaign
		else "New Game now starts in '%s'.%s" % [m.name, "" if m.built else " Play or Test Play it once to build it."])
	_refresh_modules(m.id)

func _on_delete_pressed() -> void:
	var m := _selected_module()
	if m.is_empty():
		return
	_ask("Delete the module '%s' and all of its floors?\nThis cannot be undone." % m.name, func():
		ModuleLibrary.delete_module(m.id)
		_browser_status.text = "Deleted '%s'." % m.name
		_refresh_modules())

func _on_main_menu_pressed() -> void:
	FadeManager.transition_to_scene(MENU_SCENE)
#endregion


#region Editor screen: construction
func _build_editor() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_editor = margin
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# --- Top bar ---
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	top.add_child(_btn("◀ Modules", _on_back_to_modules, "Save and go back to the module list."))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(260, 0)
	_name_edit.tooltip_text = "The module's name."
	_name_edit.text_changed.connect(func(t):
		_dungeon.dungeon_name = t
		_mark_dirty())
	top.add_child(_name_edit)
	top.add_child(VSeparator.new())
	top.add_child(_lbl("Floor"))
	_floor_opt = OptionButton.new()
	_floor_opt.custom_minimum_size = Vector2(200, 0)
	_floor_opt.item_selected.connect(_switch_floor)
	top.add_child(_floor_opt)
	_floor_name = LineEdit.new()
	_floor_name.custom_minimum_size = Vector2(170, 0)
	_floor_name.tooltip_text = "Rename this floor."
	_floor_name.text_changed.connect(_on_floor_renamed)
	top.add_child(_floor_name)
	top.add_child(_btn("＋ Floor", _on_add_floor, "Add another floor to this module."))
	top.add_child(_btn("✕", _on_remove_floor, "Remove this floor."))
	top.add_child(VSeparator.new())
	top.add_child(_btn("Undo", func(): _canvas.undo(), "Ctrl+Z"))
	top.add_child(_btn("Redo", func(): _canvas.redo(), "Ctrl+Y"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(_btn("Sky", func(): _sky_panel.open(_data),
		"Give this floor a sky with clouds and a sun, or leave it underground."))
	top.add_child(_btn("Check", _on_validate, "Look for problems on this floor."))
	top.add_child(_btn("Save", _save, "Ctrl+S"))
	top.add_child(_btn("▶ Test Play", _on_test_play, "Save, build every floor and play from the first one. F10 comes back here."))

	# --- Body: tools | map | details ---
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)
	body.add_child(_build_tools_panel())

	var map_made := _panel(Vector2(0, 0))
	(map_made[0] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(map_made[0])
	_canvas = CanvasScript.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.select_existing = true
	_canvas.changed.connect(_mark_dirty)
	_canvas.status.connect(func(t): if t != "": _status.text = t)
	_canvas.object_selected.connect(_on_object_selected)
	_canvas.edge_selected.connect(_on_edge_selected)
	(map_made[1] as VBoxContainer).add_child(_canvas)

	body.add_child(_build_details_panel())

	# --- Status line ---
	_status = _lbl("", 18, UIStyle.GOLD_BRIGHT)
	_status.clip_text = true
	root.add_child(_status)

func _build_tools_panel() -> Control:
	# Everything above the palette is kept compact (layers two to a row, no
	# headings on the small tool groups) so the palette gets the height.
	var made := _panel(Vector2(340, 0))
	var box: VBoxContainer = made[1]
	box.add_theme_constant_override("separation", 6)

	box.add_child(_heading("What to paint"))
	var layer_grid := GridContainer.new()
	layer_grid.columns = 2
	box.add_child(layer_grid)
	var layer_group := ButtonGroup.new()
	for layer in LAYERS:
		var b := _toggle(layer[1], layer_group, _set_layer.bind(layer[0]), layer[2])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		b.clip_text = true
		_layer_buttons.append(b)
		layer_grid.add_child(b)
	_hint = _lbl("", 15, UIStyle.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)

	# Floor-only shape tools.
	_tool_box = VBoxContainer.new()
	box.add_child(_tool_box)
	var grid := GridContainer.new()
	grid.columns = 2
	_tool_box.add_child(grid)
	var tool_group := ButtonGroup.new()
	var tips := ["Paint one cell at a time.", "Drag a box of floor.",
		"Drag a box of floor with walls around it.", "Fill an enclosed area."]
	for i in TOOLS.size():
		var b := _toggle(TOOLS[i], tool_group, _set_tool.bind(i), tips[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == 0
		grid.add_child(b)
	_tool_box.add_child(_btn("Auto-Wall", _on_auto_wall,
		"Wall off every floor side that faces empty space. Doors and openings between rooms are kept."))

	# Texture layers only: paint every wall (or all the floor) at once.
	_texture_box = HBoxContainer.new()
	box.add_child(_texture_box)
	_texture_all_button = _btn("Paint All Walls", _on_texture_all)
	_texture_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texture_box.add_child(_texture_all_button)
	_ceiling_clear_button = _btn("Remove All", _on_clear_ceilings,
		"Take every ceiling off this floor, opening it to the sky again.")
	_ceiling_clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texture_box.add_child(_ceiling_clear_button)

	# Facing, for objects and the start point.
	_facing_box = HBoxContainer.new()
	box.add_child(_facing_box)
	_facing_box.add_child(_lbl("Facing"))
	var facing_row := HBoxContainer.new()
	facing_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facing_box.add_child(facing_row)
	var facing_group := ButtonGroup.new()
	for i in FACINGS.size():
		var b := _toggle(FACINGS[i].substr(0, 1), facing_group, _set_facing.bind(i), FACINGS[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == 0
		facing_row.add_child(b)

	_palette_label = _heading("Palette")
	box.add_child(_palette_label)
	_palette = ItemList.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.custom_minimum_size = Vector2(0, 160)
	_palette.item_selected.connect(_on_palette_selected)
	box.add_child(_palette)

	var erase := CheckButton.new()
	erase.text = "Erase with left click"
	erase.tooltip_text = "Right-click always erases; turn this on to erase with the left button too."
	erase.toggled.connect(func(on): _canvas.force_erase = on)
	box.add_child(erase)

	_blueprint_toggle = CheckButton.new()
	_blueprint_toggle.text = "Show the floor below"
	_blueprint_toggle.tooltip_text = "Draw a blue blueprint of the floor underneath this one: the floor its pit traps drop to, or else the next floor in the list."
	_blueprint_toggle.button_pressed = true
	_blueprint_toggle.toggled.connect(func(_on): _status.text = _update_blueprint())
	box.add_child(_blueprint_toggle)

	var size_row := HBoxContainer.new()
	box.add_child(size_row)
	size_row.add_child(_lbl("Map"))
	_w_spin = _spin()
	_h_spin = _spin()
	size_row.add_child(_w_spin)
	size_row.add_child(_lbl("×"))
	size_row.add_child(_h_spin)
	size_row.add_child(_btn("Resize", _on_resize, "Change this floor's size in cells. What still fits is kept."))
	return made[0]

func _spin() -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 2
	s.max_value = 64
	s.step = 1
	return s

func _build_details_panel() -> Control:
	var made := _panel(Vector2(380, 0))
	var box: VBoxContainer = made[1]
	box.add_child(_heading("Selected"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_props = VBoxContainer.new()
	_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_props.add_theme_constant_override("separation", 6)
	scroll.add_child(_props)

	_problems_title = _heading("Problems")
	box.add_child(_problems_title)
	_problems_list = ItemList.new()
	_problems_list.custom_minimum_size = Vector2(0, 230)
	_problems_list.auto_height = false
	_problems_list.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_problems_list.tooltip_text = "Click a problem to jump to it on the map."
	_problems_list.item_selected.connect(_on_problem_selected)
	box.add_child(_problems_list)
	return made[0]

func _build_popups() -> void:
	_confirm = ConfirmationDialog.new()
	_confirm.theme = theme
	_confirm.confirmed.connect(func():
		var action := _confirm_action
		_confirm_action = Callable()
		if action.is_valid():
			action.call())
	add_child(_confirm)

	_picker = PopupPanel.new()
	_picker.theme = theme
	add_child(_picker)
	var pbox := VBoxContainer.new()
	_picker.add_child(pbox)
	pbox.add_child(_heading("Choose"))
	_picker_list = ItemList.new()
	_picker_list.custom_minimum_size = Vector2(460, 480)
	_picker_list.item_clicked.connect(func(i, _pos, _button): _on_picker_chosen(i))
	pbox.add_child(_picker_list)
	pbox.add_child(_btn("Cancel", func(): _picker.hide()))

	_sky_panel = SkyPanelScript.new()
	_sky_panel.theme = theme
	_sky_panel.changed.connect(_mark_dirty)
	add_child(_sky_panel)

	_scene_dialog = FileDialog.new()
	_scene_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_scene_dialog.access = FileDialog.ACCESS_RESOURCES
	_scene_dialog.add_filter("*.tscn", "Level scene")
	_scene_dialog.file_selected.connect(func(path):
		if _scene_edit:
			_scene_edit.text = path
		_set_param(_scene_param, path))
	add_child(_scene_dialog)

func _ask(text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_confirm_action = action
	_confirm.popup_centered()
#endregion


#region Opening / saving / floors
func _open_module(id: String) -> void:
	var dungeon := ModuleLibrary.load_module(id)
	if dungeon == null:
		_show_browser()
		_browser_status.text = "Could not open that module."
		return
	_module_id = id
	_dungeon = dungeon
	_browser.visible = false
	_editor.visible = true
	_name_edit.text = _dungeon.dungeon_name
	_dirty = false
	_set_problems([], false)
	_switch_floor(0)
	_layer_buttons[0].button_pressed = true
	_set_layer(LAYER_FLOOR)
	_status.text = "Editing '%s'. Mouse wheel zooms, middle-drag pans." % _dungeon.dungeon_name

func _mark_dirty() -> void:
	_dirty = true

func _save() -> bool:
	if _dungeon == null:
		return false
	var err := ModuleLibrary.save_module(_module_id, _dungeon)
	_dirty = err != OK
	_status.text = "Saved." if err == OK else "Save failed: %s" % error_string(err)
	return err == OK

func _on_back_to_modules() -> void:
	_save()
	_show_browser()
	_refresh_modules(_module_id)

func _switch_floor(i: int) -> void:
	_active = clampi(i, 0, _dungeon.floor_count() - 1)
	_data = _dungeon.get_floor(_active)
	_sel = { "type": "none" }
	_canvas.setup(_data, _catalog)
	_update_blueprint()
	_fit_map()
	_w_spin.value = _data.width
	_h_spin.value = _data.height
	_refresh_floor_list()
	_rebuild_props()

# Show (or hide) the blueprint of the floor below this one on the map. Returns a
# line for the status bar saying which floor that is.
func _update_blueprint() -> String:
	var below: GridLevelData = null
	if _blueprint_toggle.button_pressed:
		below = LevelFloorLinks.floor_below(_dungeon, _data, _catalog)
	_canvas.set_underlay(below)
	if not _blueprint_toggle.button_pressed:
		return "Blueprint hidden."
	if below == null:
		return "There is no floor below this one to show."
	return "Blueprint (blue): '%s', the floor below." % below.level_name

# Fill the map area with the floor once the layout has settled this frame.
func _fit_map() -> void:
	await get_tree().process_frame
	if is_instance_valid(_canvas):
		_canvas.fit_view()

func _refresh_floor_list() -> void:
	_floor_opt.clear()
	for i in _dungeon.floor_count():
		_floor_opt.add_item("%d: %s" % [i + 1, _dungeon.get_floor(i).level_name])
	_floor_opt.select(_active)
	if _floor_name.text != _data.level_name:
		_floor_name.text = _data.level_name

func _on_floor_renamed(text: String) -> void:
	_data.level_name = text
	_floor_opt.set_item_text(_active, "%d: %s" % [_active + 1, text])
	_mark_dirty()

func _on_add_floor() -> void:
	_dungeon.add_floor("", _data.width, _data.height)
	_mark_dirty()
	_switch_floor(_dungeon.floor_count() - 1)
	_status.text = "Added a floor. Connect it with stairs: place Stairs on both floors and set 'Leads to floor'."

func _on_remove_floor() -> void:
	if _dungeon.floor_count() <= 1:
		_status.text = "A module needs at least one floor."
		return
	_ask("Remove the floor '%s'?" % _data.level_name, func():
		_dungeon.remove_floor(_active)
		_mark_dirty()
		_switch_floor(mini(_active, _dungeon.floor_count() - 1)))

func _on_resize() -> void:
	_data.resize(int(_w_spin.value), int(_h_spin.value))
	_canvas.setup(_data, _catalog)
	_fit_map()
	_mark_dirty()
#endregion


#region Layers / palette / tools
func _set_layer(layer: int) -> void:
	_canvas.active_layer = layer
	for row in LAYERS:
		if row[0] == layer:
			_hint.text = row[2]
	_tool_box.visible = layer == LAYER_FLOOR
	var texturing := layer == LAYER_TEXTURE or layer == LAYER_FLOOR_TEXTURE or layer == LAYER_CEILING
	_texture_box.visible = texturing
	_ceiling_clear_button.visible = layer == LAYER_CEILING
	match layer:
		LAYER_FLOOR_TEXTURE:
			_texture_all_button.text = "Paint All Floor"
			_texture_all_button.tooltip_text = "Give all the floor on this level the chosen texture."
		LAYER_CEILING:
			_texture_all_button.text = "Roof All"
			_texture_all_button.tooltip_text = "Put a ceiling with the chosen texture over all the floor on this level."
		_:
			_texture_all_button.text = "Paint All Walls"
			_texture_all_button.tooltip_text = "Give every wall on this floor the chosen texture."
	_facing_box.visible = layer == LAYER_OBJECT or layer == LAYER_SPAWN
	var has_palette := layer <= LAYER_OBJECT or texturing
	_palette_label.visible = has_palette
	_palette.visible = has_palette
	_palette.clear()
	_palette_tiles.clear()
	_palette_textures.clear()
	_palette.fixed_icon_size = Vector2i(44, 44)
	if texturing:
		_fill_texture_palette()
		_canvas.queue_redraw()
		return
	if not has_palette:
		_canvas.queue_redraw()
		return
	var tiles: Array = []
	match layer:
		LAYER_FLOOR: tiles = _catalog.floor_tiles()
		LAYER_EDGE: tiles = _catalog.edge_tiles()
		LAYER_OBJECT: tiles = _catalog.object_tiles()
	for t in tiles:
		var icon := LevelTileIcons.badge(t)
		_palette.add_item(t.display_name, icon if icon else _swatch(t.color))
		_palette_tiles.append(t)
	if _palette.item_count > 0:
		_palette.select(0)
		_on_palette_selected(0)
	_canvas.queue_redraw()

# The texture the active texture layer paints with (each layer keeps its own).
func _active_texture() -> String:
	match _canvas.active_layer:
		LAYER_FLOOR_TEXTURE: return _canvas.active_floor_texture
		LAYER_CEILING: return _canvas.active_ceiling_texture
	return _canvas.active_texture

# The texture palette: "Plain" first, then every texture set with its preview.
func _fill_texture_palette() -> void:
	var plain := Color(0.36, 0.31, 0.26)
	match _canvas.active_layer:
		LAYER_FLOOR_TEXTURE: plain = Color(0.62, 0.55, 0.42)
		LAYER_CEILING: plain = Color(0.30, 0.26, 0.22)
	_palette.add_item("Plain (no texture)", _swatch(plain))
	_palette_textures.append("")
	for texture in WallTextures.names():
		_palette.add_item(WallTextures.label(texture), WallTextures.preview(texture))
		_palette_textures.append(texture)
	var pick := maxi(_palette_textures.find(_active_texture()), 0)
	if pick == 0 and _palette_textures.size() > 1 and _canvas.active_layer != LAYER_CEILING:
		pick = 1   # start on a real texture rather than "Plain" (a plain ceiling is a fine start)
	_palette.select(pick)
	_on_palette_selected(pick)

func _on_texture_all() -> void:
	var texture := _active_texture()
	var what := WallTextures.label(texture) if texture != "" else "plain"
	if _canvas.active_layer == LAYER_CEILING:
		var roofed: int = _canvas.ceiling_all_floors(texture)
		_status.text = "Roofed %d cell%s (%s)." % [roofed, "" if roofed == 1 else "s", what] if roofed > 0 \
			else "All the floor on this level already has that ceiling."
		return
	if _canvas.active_layer == LAYER_FLOOR_TEXTURE:
		var cells: int = _canvas.texture_all_floors(texture)
		_status.text = "Painted %d floor cell%s %s." % [cells, "" if cells == 1 else "s", what] if cells > 0 \
			else "All the floor on this level is already %s." % what
		return
	var count: int = _canvas.texture_all_walls(texture)
	_status.text = "Painted %d wall%s %s." % [count, "" if count == 1 else "s", what] if count > 0 \
		else "Every wall on this floor is already %s." % what

func _on_clear_ceilings() -> void:
	var count: int = _canvas.clear_ceilings()
	_status.text = "Removed %d ceiling cell%s." % [count, "" if count == 1 else "s"] if count > 0 \
		else "This floor has no ceilings."

func _on_palette_selected(index: int) -> void:
	if _canvas.active_layer in [LAYER_TEXTURE, LAYER_FLOOR_TEXTURE, LAYER_CEILING]:
		if index >= 0 and index < _palette_textures.size():
			match _canvas.active_layer:
				LAYER_FLOOR_TEXTURE: _canvas.active_floor_texture = _palette_textures[index]
				LAYER_CEILING: _canvas.active_ceiling_texture = _palette_textures[index]
				_: _canvas.active_texture = _palette_textures[index]
		return
	if index < 0 or index >= _palette_tiles.size():
		return
	var t: TileDef = _palette_tiles[index]
	match t.kind:
		TileDef.Kind.FLOOR: _canvas.active_floor_id = t.id
		TileDef.Kind.EDGE: _canvas.active_edge_id = t.id
		TileDef.Kind.OBJECT: _canvas.active_object_id = t.name_id

func _swatch(col: Color) -> ImageTexture:
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)

func _set_tool(index: int) -> void:
	_canvas.tool = index

func _set_facing(index: int) -> void:
	_canvas.active_facing = index

func _on_auto_wall() -> void:
	var added: int = _canvas.auto_wall()
	_status.text = "Auto-Wall added %d wall%s." % [added, "" if added == 1 else "s"] if added > 0 \
		else "Auto-Wall: every edge is already closed."
#endregion


#region Selected object / door
func _on_object_selected(cell: Vector2i) -> void:
	_sel = { "type": "none" } if cell.x < 0 else { "type": "object", "cell": cell }
	_rebuild_props()

func _on_edge_selected(axis: String, a: int, b: int) -> void:
	_sel = { "type": "none" } if axis == "" else { "type": "edge", "axis": axis, "a": a, "b": b }
	_rebuild_props()

func _rebuild_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	var def: TileDef = null
	var values: Dictionary = {}
	match _sel.get("type", "none"):
		"object":
			var entry := _data.get_object(_sel.cell.x, _sel.cell.y)
			if entry.is_empty():
				_props_hint()
				return
			def = _catalog.get_object(entry.get("id", &""))
			values = entry.get("params", {})
			_add_props_icon(def)
			_props.add_child(_lbl("%s at (%d, %d)" % [def.display_name if def else "?", _sel.cell.x, _sel.cell.y], 22, UIStyle.GOLD_BRIGHT))
			var actions := HBoxContainer.new()
			_props.add_child(actions)
			actions.add_child(_btn("Turn ↻", _rotate_selected, "Turn it to face the next direction."))
			actions.add_child(_btn("Remove", _remove_selected))
			_props.add_child(_lbl("Facing %s" % FACINGS[int(entry.get("facing", 0)) % 4], 16, UIStyle.MUTED))
		"edge":
			var id := _data.get_edge_v(_sel.a, _sel.b) if _sel.axis == "V" else _data.get_edge_h(_sel.a, _sel.b)
			def = _catalog.get_by_id(TileDef.Kind.EDGE, id)
			if def == null:
				_props_hint()
				return
			values = _data.get_edge_params(_sel.axis, _sel.a, _sel.b)
			_add_props_icon(def)
			_props.add_child(_lbl(def.display_name, 22, UIStyle.GOLD_BRIGHT))
			_props.add_child(_btn("Remove", _remove_selected))
		_:
			_props_hint()
			return
	if def == null or def.params.is_empty():
		_props.add_child(_lbl("Nothing to set on this.", 16, UIStyle.MUTED))
		return
	for p in def.params:
		_add_param_field(p, values)

# The selected tile's picture, at the top of the Selected panel.
func _add_props_icon(def: TileDef) -> void:
	var icon := LevelTileIcons.badge(def)
	if icon == null:
		return
	var picture := TextureRect.new()
	picture.texture = icon
	picture.custom_minimum_size = Vector2(96, 96)
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	picture.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_props.add_child(picture)

func _props_hint() -> void:
	var l := _lbl("Click an object or a door on the map to edit it here.", 16, UIStyle.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_props.add_child(l)

func _rotate_selected() -> void:
	if _sel.get("type", "") != "object":
		return
	var entry := _data.get_object(_sel.cell.x, _sel.cell.y)
	if entry.is_empty():
		return
	_data.set_object(_sel.cell.x, _sel.cell.y, entry.id, (int(entry.get("facing", 0)) + 1) % 4)
	_after_edit()

func _remove_selected() -> void:
	match _sel.get("type", "none"):
		"object": _data.erase_object(_sel.cell.x, _sel.cell.y)
		"edge":
			if _sel.axis == "V": _data.set_edge_v(_sel.a, _sel.b, 0)
			else: _data.set_edge_h(_sel.a, _sel.b, 0)
	_sel = { "type": "none" }
	_after_edit()

func _after_edit() -> void:
	_mark_dirty()
	_update_blueprint()   # a pit trap came or went: the floor below may be another
	_canvas.queue_redraw()
	_rebuild_props()

func _set_param(pname: String, value) -> void:
	match _sel.get("type", "none"):
		"object": _data.set_object_param(_sel.cell.x, _sel.cell.y, pname, value)
		"edge": _data.set_edge_param(_sel.axis, _sel.a, _sel.b, pname, value)
		_: return
	_mark_dirty()

func _current_param(pname: String):
	match _sel.get("type", "none"):
		"object": return _data.get_object(_sel.cell.x, _sel.cell.y).get("params", {}).get(pname, null)
		"edge": return _data.get_edge_params(_sel.axis, _sel.a, _sel.b).get(pname, null)
	return null

# One labelled editor per parameter in the tile's schema (TileDef.params).
func _add_param_field(p: Dictionary, values: Dictionary) -> void:
	var pname: String = p.get("name", "")
	var val = values.get(pname, p.get("default", null))
	var label := _lbl(String(p.get("label", pname)), 16, UIStyle.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_props.add_child(label)
	match p.get("type", "string"):
		"int", "float":
			var s := SpinBox.new()
			s.min_value = -999999
			s.max_value = 999999
			s.step = 1.0 if p.type == "int" else 0.1
			s.value = float(val) if val != null else 0.0
			s.value_changed.connect(func(v): _set_param(pname, int(v) if p.type == "int" else float(v)))
			_props.add_child(s)
		"bool":
			var cb := CheckBox.new()
			cb.text = "Yes"
			cb.button_pressed = bool(val) if val != null else false
			cb.toggled.connect(func(on): _set_param(pname, on))
			_props.add_child(cb)
		"enum":
			var ob := OptionButton.new()
			for opt in p.get("options", []):
				ob.add_item(str(opt))
			if ob.item_count > 0:
				ob.select(clampi(int(val) if val != null else 0, 0, ob.item_count - 1))
			ob.item_selected.connect(func(picked): _set_param(pname, picked))
			_props.add_child(ob)
		"int_list":
			var il := LineEdit.new()
			il.text = ", ".join((val as Array).map(func(v): return str(int(v)))) if val is Array else ""
			il.placeholder_text = "e.g. 3, 6, 2, 6"
			il.text_changed.connect(func(t): _set_param(pname, _parse_int_list(t)))
			_props.add_child(il)
		"floor_link":
			var fo := OptionButton.new()
			fo.add_item("Nowhere yet")
			fo.set_item_metadata(0, "")
			for i in _dungeon.floor_count():
				var f := _dungeon.get_floor(i)
				if f == _data:
					continue
				fo.add_item("%d: %s" % [i + 1, f.level_name])
				fo.set_item_metadata(fo.item_count - 1, f.uid)
				if f.uid == str(val):
					fo.select(fo.item_count - 1)
			fo.item_selected.connect(func(picked):
				_set_param(pname, fo.get_item_metadata(picked))
				_update_blueprint()
				_rebuild_props.call_deferred())   # the arrival choices depend on the floor
			_props.add_child(fo)
		"arrival":
			var ao := OptionButton.new()
			ao.add_item("The cell directly below" if _selected_is_pit() else "The matching stairs / door")
			ao.set_item_metadata(0, LevelFloorLinks.ARRIVE_AUTO)
			ao.add_item("That floor's start point")
			ao.set_item_metadata(1, LevelFloorLinks.ARRIVE_SPAWN)
			var target := _dungeon.floor_by_uid(str(values.get(LevelFloorLinks.PARAM_FLOOR, "")))
			for c in LevelFloorLinks.arrival_points(target, _catalog):
				ao.add_item(c.label)
				ao.set_item_metadata(ao.item_count - 1, c.key)
			for i in ao.item_count:
				if ao.get_item_metadata(i) == str(val if val != null else ""):
					ao.select(i)
			ao.disabled = target == null
			ao.item_selected.connect(func(picked): _set_param(pname, ao.get_item_metadata(picked)))
			_props.add_child(ao)
		"wall_texture":
			var to := OptionButton.new()
			to.add_item("Plain")
			to.set_item_metadata(0, "")
			for texture in WallTextures.names():
				to.add_item(WallTextures.label(texture))
				to.set_item_metadata(to.item_count - 1, texture)
				if texture == str(val if val != null else ""):
					to.select(to.item_count - 1)
			to.item_selected.connect(func(picked):
				_set_param(pname, to.get_item_metadata(picked))
				_canvas.queue_redraw())
			_props.add_child(to)
		"resource_list":
			_add_list_field(pname, val, String(p.get("browse", "res://")))
		"scene_path":
			var row := HBoxContainer.new()
			var le := LineEdit.new()
			le.text = str(val) if val != null else ""
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(t): _set_param(pname, t))
			row.add_child(le)
			row.add_child(_btn("…", func():
				_scene_edit = le
				_scene_param = pname
				_scene_dialog.popup_centered_ratio(0.6)))
			_props.add_child(row)
		_:
			var le := LineEdit.new()
			le.text = str(val) if val != null else ""
			le.text_changed.connect(func(t): _set_param(pname, t))
			_props.add_child(le)

func _selected_is_pit() -> bool:
	if _sel.get("type", "none") != "object":
		return false
	var def := _catalog.get_object(_data.get_object(_sel.cell.x, _sel.cell.y).get("id", &""))
	return def != null and def.is_pit

func _parse_int_list(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var s := part.strip_edges()
		if s.is_valid_int():
			out.append(int(s))
	return out

# A list of files (chest items, encounter monsters): one row each with a remove
# button, and an Add button that opens a picker of what is in the `browse` folder.
func _add_list_field(pname: String, val, browse: String) -> void:
	var list: Array = val.duplicate() if val is Array else []
	if list.is_empty():
		_props.add_child(_lbl("  (none)", 16, UIStyle.MUTED))
	for i in list.size():
		var row := HBoxContainer.new()
		var name_lbl := _lbl("• " + _pretty_name(String(list[i])), 18)
		name_lbl.tooltip_text = String(list[i])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		row.add_child(name_lbl)
		var index := i
		row.add_child(_btn("✕", func():
			var shorter: Array = list.duplicate()
			shorter.remove_at(index)
			_set_param(pname, shorter)
			_rebuild_props()))
		_props.add_child(row)
	_props.add_child(_btn("＋ Add…", func(): _open_picker(pname, browse)))

func _pretty_name(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").capitalize()

func _open_picker(pname: String, folder: String) -> void:
	_picker_param = pname
	_picker_list.clear()
	var files: Array = []
	_collect_files(folder, ".tres", files)
	files.sort()
	for path in files:
		_picker_list.add_item(_pretty_name(path))
		_picker_list.set_item_metadata(_picker_list.item_count - 1, path)
		_picker_list.set_item_tooltip(_picker_list.item_count - 1, path)
	if files.is_empty():
		_picker_list.add_item("(nothing found in %s)" % folder)
		_picker_list.set_item_disabled(0, true)
	_picker.popup_centered()

func _collect_files(folder: String, extension: String, into: Array) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect_files(folder.path_join(sub), extension, into)
	for file in dir.get_files():
		# Exported games list resources as "<name>.remap"; strip that to get the path.
		var clean := file.trim_suffix(".remap")
		if clean.ends_with(extension):
			into.append(folder.path_join(clean))

func _on_picker_chosen(index: int) -> void:
	var path = _picker_list.get_item_metadata(index)
	_picker.hide()
	if not (path is String) or _picker_param == "":
		return
	var current = _current_param(_picker_param)
	var list: Array = current.duplicate() if current is Array else []
	list.append(path)
	_set_param(_picker_param, list)
	_rebuild_props()
#endregion


#region Problems / test play
func _on_validate() -> void:
	var summary := _set_problems(LevelValidator.validate(_dungeon, _data, _catalog).map(func(p):
		p["floor"] = _active
		return p), false)
	_status.text = "No problems found on this floor." if summary == "" else "Found %s." % summary

## Show a list of problems (each tagged with its floor index); returns the summary.
func _set_problems(problems: Array, name_floors: bool) -> String:
	_problems = problems
	_problems_list.clear()
	for p in _problems:
		var prefix := "✖ " if p.severity == LevelValidator.ERROR else "⚠ "
		if name_floors:
			prefix += "[%s] " % _dungeon.get_floor(p.floor).level_name
		var row := _problems_list.add_item(prefix + p.text)
		_problems_list.set_item_tooltip(row, p.text)
		_problems_list.set_item_custom_fg_color(row,
			Color(1.0, 0.5, 0.45) if p.severity == LevelValidator.ERROR else Color(1.0, 0.84, 0.4))
	var summary: String = LevelValidator.summary(_problems)
	_problems_title.text = "Problems" if summary == "" else "Problems — " + summary
	return summary

func _on_problem_selected(index: int) -> void:
	if index < 0 or index >= _problems.size():
		return
	var p: Dictionary = _problems[index]
	if p.floor != _active:
		_switch_floor(p.floor)
	if p.cell.x >= 0:
		_canvas.focus_cell(p.cell)

func _on_test_play() -> void:
	if not _save():
		return
	var all: Array = []
	for i in _dungeon.floor_count():
		for p in LevelValidator.validate(_dungeon, _dungeon.get_floor(i), _catalog):
			p["floor"] = i
			all.append(p)
	_set_problems(all, _dungeon.floor_count() > 1)
	if all.any(func(p): return p.severity == LevelValidator.ERROR):
		_ask("This module has errors (listed under Problems).\nPlay it anyway?", func():
			_status.text = _build_and_launch(_module_id, _dungeon))
		return
	_status.text = _build_and_launch(_module_id, _dungeon)

## Build every floor of a module and start playing it. On success this screen is
## freed (LevelManager takes over); on failure the returned text says why.
func _build_and_launch(id: String, dungeon: DungeonData) -> String:
	if dungeon == null:
		return "Could not open that module."
	var report := ModuleLibrary.build_module(id, dungeon)
	if not report.ok:
		return "Build failed: " + "; ".join(report.errors)
	var start := ModuleLibrary.start_scene(dungeon)
	if start == "":
		return "Nothing to play: the first floor could not be built."

	# A fresh adventure: default heroes, empty backpack, clean world and map.
	GameState.editor_test_module = id
	PartyManager.reset()
	PartyManager.create_new_party(false)
	PartyManager.is_initialized = true
	WorldState.reset()
	if InventoryManager.has_method("reset_inventory"):
		InventoryManager.reset_inventory()
	LevelManager.load_level(start)
	queue_free()
	return "Starting '%s'…" % dungeon.dungeon_name
#endregion
