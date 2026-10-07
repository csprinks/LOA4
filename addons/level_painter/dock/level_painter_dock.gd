@tool
extends Control

## The Level Painter dock UI: toolbar (new/open/save/build), layer + palette pickers,
## grid resize, and the paint canvas. Built entirely in code so there is no fragile
## companion .tscn. Runs in the editor only (@tool).

const CanvasScript := preload("res://addons/level_painter/dock/level_paint_canvas.gd")
const BuilderScript := preload("res://addons/level_painter/grid_level_builder.gd")
const DataScript := preload("res://addons/level_painter/grid_level_data.gd")
const DungeonScript := preload("res://addons/level_painter/dungeon_data.gd")
const CatalogScript := preload("res://addons/level_painter/tile_catalog.gd")
const LinkKeeperScript := preload("res://addons/level_painter/link_keeper.gd")
const FloorLinksScript := preload("res://addons/level_painter/floor_links.gd")
const ValidatorScript := preload("res://addons/level_painter/level_validator.gd")
const PaintedLinksScript := preload("res://addons/level_painter/painted_links.gd")
const PipelineScript := preload("res://addons/level_painter/build_pipeline.gd")
const DEFAULT_CATALOG := "res://addons/level_painter/default_catalog.tres"
const PLAYER_LOADING := "res://Scenes/player_loading.gd"
const META_DATA := PipelineScript.META_DATA   ## meta key that carries the paint data in a built .tscn

var _dungeon: DungeonData          # the whole multi-floor dungeon (source of truth)
var _active := 0                   # index of the floor currently being painted
var _data: GridLevelData           # == _dungeon.floors[_active]; most code uses this
var _catalog: TileCatalog
var _res_path := ""
var _carried := {}                 # links / nodes kept by the build(s) in progress (status text)
var _link_warnings: Array = []     # floor-connection problems from the build(s) in progress
var _play_after_build := false     # the open Build dialog was raised by Build & Play
var _problems: Array = []          # validation results shown in the Problems list (index-aligned)
var _problems_box: VBoxContainer
var _problems_title: Label
var _problems_list: ItemList

var _canvas
var _palette: ItemList
var _layer_opt: OptionButton
var _tool_opt: OptionButton
var _facing_opt: OptionButton
var _erase_chk: CheckButton
var _path_label: Label
var _status_label: Label
var _w_spin: SpinBox
var _h_spin: SpinBox
var _open_dialog: EditorFileDialog
var _save_dialog: EditorFileDialog
var _build_dialog: EditorFileDialog
var _build_all_dialog: EditorFileDialog
var _scene_pick_dialog: EditorFileDialog
var _floor_opt: OptionButton
var _floor_name_edit: LineEdit

var _props_box: VBoxContainer
var _sel := { "type": "none" }             # what the props panel is editing: object or edge
var _pending_scene_edit: LineEdit          # which field a scene-pick dialog fills
var _pending_scene_param := ""
var _item_pick_dialog: EditorFileDialog    # picks item resources for a resource_list
var _pending_list_param := ""

# Rows of TileDef currently shown in the palette (index-aligned with the ItemList).
var _palette_tiles: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(0, 320)
	_load_catalog()
	_build_ui()
	_new_level(16, 16)

## Always read the catalog fresh from disk (CACHE_MODE_IGNORE) so a stale
## session-cached copy — e.g. one loaded before new tile fields existed — can't
## silently use outdated tile definitions at build time.
func _load_catalog() -> void:
	if ResourceLoader.exists(DEFAULT_CATALOG):
		_catalog = ResourceLoader.load(DEFAULT_CATALOG, "", ResourceLoader.CACHE_MODE_IGNORE)
	else:
		_catalog = CatalogScript.default_catalog()


#region UI construction
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# --- Toolbar row 1: file ops ---
	var bar1 := HBoxContainer.new()
	root.add_child(bar1)
	bar1.add_child(_btn("New", _on_new))
	bar1.add_child(_btn("Open…", _on_open))
	bar1.add_child(_btn("Save", _on_save))
	bar1.add_child(_btn("Save As…", _on_save_as))
	bar1.add_child(_vsep())
	bar1.add_child(_btn("Build Level…", _on_build))
	var play_btn := _btn("▶ Build & Play", _on_build_and_play)
	play_btn.tooltip_text = "Rebuild this floor where it was last built and run it. Asks where to build it the first time."
	bar1.add_child(play_btn)
	var validate_btn := _btn("Validate", _on_validate)
	validate_btn.tooltip_text = "Check this floor for problems. Also runs automatically before every build."
	bar1.add_child(validate_btn)
	bar1.add_child(_btn("Reload Catalog", _on_reload_catalog))
	bar1.add_child(_vsep())
	_path_label = Label.new()
	_path_label.text = "(unsaved)"
	_path_label.modulate = Color(0.7, 0.7, 0.7)
	bar1.add_child(_path_label)

	# --- Floor row: pick / add / remove / rename floors, build the whole dungeon ---
	var barf := HBoxContainer.new()
	root.add_child(barf)
	barf.add_child(_lbl("Floor:"))
	_floor_opt = OptionButton.new()
	_floor_opt.item_selected.connect(_on_floor_selected)
	barf.add_child(_floor_opt)
	barf.add_child(_btn("＋ Add Floor", _on_add_floor))
	barf.add_child(_btn("✕ Remove Floor", _on_remove_floor))
	barf.add_child(_lbl("Name:"))
	_floor_name_edit = LineEdit.new()
	_floor_name_edit.custom_minimum_size = Vector2(120, 0)
	_floor_name_edit.text_changed.connect(_on_floor_renamed)
	barf.add_child(_floor_name_edit)
	barf.add_child(_vsep())
	barf.add_child(_btn("Build All Floors…", _on_build_all))

	# --- Toolbar row 2: paint controls ---
	var bar2 := HBoxContainer.new()
	root.add_child(bar2)
	bar2.add_child(_lbl("Layer:"))
	_layer_opt = OptionButton.new()
	_layer_opt.add_item("Floor", _canvas_layer_floor())
	_layer_opt.add_item("Walls & Doors", 1)
	_layer_opt.add_item("Objects", 2)
	_layer_opt.add_item("Spawn Point", 3)
	_layer_opt.add_item("Links", 4)
	_layer_opt.add_item("Wear", CanvasScript.LAYER_WEAR)
	_layer_opt.item_selected.connect(_on_layer_changed)
	bar2.add_child(_layer_opt)

	# Floor-layer shape tools + one-click wall-off.
	bar2.add_child(_lbl("Tool:"))
	_tool_opt = OptionButton.new()
	for t in ["Brush", "Rectangle", "Room (floor + walls)", "Fill"]:
		_tool_opt.add_item(t)
	_tool_opt.tooltip_text = "Floor layer only. Rectangle/Room: drag a box. Fill: click an area. Right-click erases."
	_tool_opt.item_selected.connect(func(i): if _canvas: _canvas.tool = i)
	bar2.add_child(_tool_opt)
	var auto_wall_btn := _btn("Auto-Wall", _on_auto_wall)
	auto_wall_btn.tooltip_text = "Add a wall on every floor side that faces empty space. Existing walls and doors are kept."
	bar2.add_child(auto_wall_btn)

	bar2.add_child(_lbl("Facing:"))
	_facing_opt = OptionButton.new()
	for f in ["North", "East", "South", "West"]:
		_facing_opt.add_item(f)
	_facing_opt.item_selected.connect(func(i): if _canvas: _canvas.active_facing = i)
	bar2.add_child(_facing_opt)

	_erase_chk = CheckButton.new()
	_erase_chk.text = "Erase (or right-click)"
	_erase_chk.toggled.connect(func(on): if _canvas: _canvas.force_erase = on)
	bar2.add_child(_erase_chk)

	bar2.add_child(_vsep())
	bar2.add_child(_btn("Undo", func(): if _canvas: _canvas.undo()))
	bar2.add_child(_btn("Redo", func(): if _canvas: _canvas.redo()))

	bar2.add_child(_vsep())
	bar2.add_child(_lbl("W:"))
	_w_spin = _spin(1, 128, 16); bar2.add_child(_w_spin)
	bar2.add_child(_lbl("H:"))
	_h_spin = _spin(1, 128, 16); bar2.add_child(_h_spin)
	bar2.add_child(_btn("Resize", _on_resize))

	# --- Body: palette | canvas ---
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var pal_box := VBoxContainer.new()
	pal_box.custom_minimum_size = Vector2(220, 0)
	body.add_child(pal_box)
	pal_box.add_child(_lbl("Palette"))
	_palette = ItemList.new()
	_palette.custom_minimum_size = Vector2(0, 150)
	_palette.fixed_icon_size = Vector2i(32, 32)
	_palette.item_selected.connect(_on_palette_selected)
	pal_box.add_child(_palette)

	pal_box.add_child(HSeparator.new())
	pal_box.add_child(_lbl("Properties"))
	var props_scroll := ScrollContainer.new()
	props_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	props_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pal_box.add_child(props_scroll)
	_props_box = VBoxContainer.new()
	_props_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	props_scroll.add_child(_props_box)

	_canvas = CanvasScript.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.changed.connect(_on_canvas_changed)
	_canvas.status.connect(func(t): _status_label.text = t)
	_canvas.object_selected.connect(_on_object_selected)
	_canvas.edge_selected.connect(_on_edge_selected)
	body.add_child(_canvas)

	# --- Problems (validation results; hidden while there are none) ---
	_problems_box = VBoxContainer.new()
	_problems_box.visible = false
	root.add_child(_problems_box)
	_problems_title = _lbl("Problems")
	_problems_box.add_child(_problems_title)
	_problems_list = ItemList.new()
	_problems_list.custom_minimum_size = Vector2(0, 96)
	_problems_list.tooltip_text = "Click a problem to jump to it on the map."
	_problems_list.item_selected.connect(_on_problem_selected)
	_problems_box.add_child(_problems_list)

	# --- Status bar ---
	_status_label = Label.new()
	_status_label.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(_status_label)

	_build_file_dialogs()
	_on_layer_changed(0)
	_rebuild_props()

func _canvas_layer_floor() -> int:
	return 0

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func _lbl(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _vsep() -> VSeparator:
	return VSeparator.new()

func _spin(minv: float, maxv: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv; s.max_value = maxv; s.value = val; s.step = 1
	return s

func _build_file_dialogs() -> void:
	_open_dialog = EditorFileDialog.new()
	_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_open_dialog.add_filter("*.tres", "Level data")
	_open_dialog.add_filter("*.tscn", "Built level")
	_open_dialog.file_selected.connect(_on_open_selected)
	add_child(_open_dialog)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.tres", "Grid Level")
	_save_dialog.file_selected.connect(_on_save_as_selected)
	add_child(_save_dialog)

	_build_dialog = EditorFileDialog.new()
	_build_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_build_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_build_dialog.add_filter("*.tscn", "Level Scene")
	_build_dialog.file_selected.connect(_on_build_selected)
	_build_dialog.canceled.connect(func(): _play_after_build = false)
	add_child(_build_dialog)

	_build_all_dialog = EditorFileDialog.new()
	_build_all_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_build_all_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_build_all_dialog.dir_selected.connect(_on_build_all_dir)
	add_child(_build_all_dialog)

	_scene_pick_dialog = EditorFileDialog.new()
	_scene_pick_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_scene_pick_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_scene_pick_dialog.add_filter("*.tscn", "Scene")
	_scene_pick_dialog.file_selected.connect(_on_scene_picked)
	add_child(_scene_pick_dialog)

	_item_pick_dialog = EditorFileDialog.new()
	_item_pick_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_item_pick_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_item_pick_dialog.add_filter("*.tres", "Item resource")
	_item_pick_dialog.file_selected.connect(_on_item_picked)
	add_child(_item_pick_dialog)
#endregion


#region Object / edge properties panel
func _on_object_selected(cell: Vector2i) -> void:
	_sel = { "type": "none" } if cell.x < 0 else { "type": "object", "cell": cell }
	_rebuild_props()

func _on_edge_selected(axis: String, a: int, b: int) -> void:
	_sel = { "type": "none" } if axis == "" else { "type": "edge", "axis": axis, "a": a, "b": b }
	_rebuild_props()

func _rebuild_props() -> void:
	for c in _props_box.get_children():
		c.queue_free()
	if _data == null:
		_props_box.add_child(_lbl("(place/click something)"))
		return
	var def: TileDef = null
	var pvals: Dictionary = {}
	var title := ""
	match _sel.get("type", "none"):
		"object":
			var entry := _data.get_object(_sel.cell.x, _sel.cell.y)
			if entry.is_empty():
				_props_box.add_child(_lbl("(place/click an object)"))
				return
			def = _catalog.get_object(entry.get("id", &"")) if _catalog else null
			pvals = entry.get("params", {})
			title = "%s @ (%d, %d)" % [(def.display_name if def else "?"), _sel.cell.x, _sel.cell.y]
		"edge":
			var id := (_data.get_edge_v(_sel.a, _sel.b) if _sel.axis == "V" else _data.get_edge_h(_sel.a, _sel.b))
			def = _catalog.get_by_id(TileDef.Kind.EDGE, id) if _catalog else null
			pvals = _data.get_edge_params(_sel.axis, _sel.a, _sel.b)
			title = "%s edge (%s %d,%d)" % [(def.display_name if def else "?"), _sel.axis, _sel.a, _sel.b]
		_:
			_props_box.add_child(_lbl("(place/click an object or door)"))
			return
	_props_box.add_child(_lbl(title))
	if def == null or def.params.is_empty():
		_props_box.add_child(_lbl("(no properties)"))
		return
	for p in def.params:
		_add_param_field(p, pvals)

func _add_param_field(p: Dictionary, pvals: Dictionary) -> void:
	var pname: String = p.get("name", "")
	var val = pvals.get(pname, p.get("default", null))
	_props_box.add_child(_lbl(p.get("label", pname) + ":"))
	match p.get("type", "string"):
		"int":
			var s := SpinBox.new()
			s.min_value = -999999; s.max_value = 999999; s.step = 1
			s.value = (int(val) if val != null else 0)
			s.value_changed.connect(func(v): _set_param(pname, int(v)))
			_props_box.add_child(s)
		"float":
			var fs := SpinBox.new()
			fs.min_value = -9999; fs.max_value = 9999; fs.step = 0.1
			fs.value = (float(val) if val != null else 0.0)
			fs.value_changed.connect(func(v): _set_param(pname, float(v)))
			_props_box.add_child(fs)
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(val) if val != null else false
			cb.toggled.connect(func(on): _set_param(pname, on))
			_props_box.add_child(cb)
		"enum":
			var ob := OptionButton.new()
			for opt in p.get("options", []):
				ob.add_item(str(opt))
			if ob.item_count > 0:
				ob.select(clampi(int(val) if val != null else 0, 0, ob.item_count - 1))
			ob.item_selected.connect(func(i): _set_param(pname, i))
			_props_box.add_child(ob)
		"floor_link":
			# Which floor of this dungeon the stairs/door leads to. The scene path and
			# arrival marker are worked out at build time (LevelFloorLinks).
			var fo := OptionButton.new()
			fo.add_item("(none — set scene by hand)")
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
				_rebuild_props.call_deferred())   # the arrival choices depend on the floor
			_props_box.add_child(fo)
		"arrival":
			var ao := OptionButton.new()
			ao.add_item("Auto (matching stairs/door, else spawn)")
			ao.set_item_metadata(0, FloorLinksScript.ARRIVE_AUTO)
			ao.add_item("That floor's spawn point")
			ao.set_item_metadata(1, FloorLinksScript.ARRIVE_SPAWN)
			var target := _dungeon.floor_by_uid(str(pvals.get(FloorLinksScript.PARAM_FLOOR, "")))
			for c in FloorLinksScript.arrival_points(target, _catalog):
				ao.add_item(c.label)
				ao.set_item_metadata(ao.item_count - 1, c.key)
			for i in ao.item_count:
				if ao.get_item_metadata(i) == str(val if val != null else ""):
					ao.select(i)
			ao.disabled = target == null
			ao.item_selected.connect(func(picked): _set_param(pname, ao.get_item_metadata(picked)))
			_props_box.add_child(ao)
		"int_list":
			var il := LineEdit.new()
			il.text = ", ".join((val as Array).map(func(v): return str(int(v)))) if val is Array else ""
			il.placeholder_text = "e.g. 3, 6, 2, 6"
			il.text_changed.connect(func(t): _set_param(pname, _parse_int_list(t)))
			_props_box.add_child(il)
		"scene_path":
			var hb := HBoxContainer.new()
			var le := LineEdit.new()
			le.text = (str(val) if val != null else "")
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(t): _set_param(pname, t))
			hb.add_child(le)
			var b := Button.new(); b.text = "…"
			b.pressed.connect(func(): _pick_scene(le, pname))
			hb.add_child(b)
			_props_box.add_child(hb)
		"resource_list":
			_add_resource_list_field(pname, val)
		_:
			var le := LineEdit.new()
			le.text = (str(val) if val != null else "")
			le.text_changed.connect(func(t): _set_param(pname, t))
			_props_box.add_child(le)

## "3, 6, 2" -> [3, 6, 2]. Anything that isn't a whole number is skipped.
func _parse_int_list(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		var s := part.strip_edges()
		if s.is_valid_int():
			out.append(int(s))
	return out

## A proper multi-item editor for a resource_list param (e.g. chest contents):
## one row per item with a remove button, plus an "Add item…" picker.
func _add_resource_list_field(pname: String, val) -> void:
	var list: Array = (val.duplicate() if val is Array else [])
	if list.is_empty():
		_props_box.add_child(_lbl("  (none)"))
	for i in list.size():
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "• " + String(list[i]).get_file()
		name_lbl.tooltip_text = String(list[i])
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		row.add_child(name_lbl)
		var rm := Button.new(); rm.text = "✕"
		var idx := i
		rm.pressed.connect(func():
			var l: Array = list.duplicate()
			l.remove_at(idx)
			_set_param(pname, l)
			_rebuild_props())
		row.add_child(rm)
		_props_box.add_child(row)
	var add_btn := Button.new()
	add_btn.text = "＋ Add item…"
	add_btn.pressed.connect(func():
		_pending_list_param = pname
		_item_pick_dialog.popup_centered_ratio(0.6))
	_props_box.add_child(add_btn)

func _on_item_picked(path: String) -> void:
	if _pending_list_param == "":
		return
	var cur = _current_param(_pending_list_param)
	var list: Array = (cur.duplicate() if cur is Array else [])
	list.append(path)
	_set_param(_pending_list_param, list)
	_rebuild_props()

## Route a param write to whatever the panel is currently editing.
func _set_param(pname: String, value) -> void:
	match _sel.get("type", "none"):
		"object": _data.set_object_param(_sel.cell.x, _sel.cell.y, pname, value)
		"edge":   _data.set_edge_param(_sel.axis, _sel.a, _sel.b, pname, value)
		_: return
	_on_canvas_changed()

## Read the current value of a param for the active selection.
func _current_param(pname: String):
	match _sel.get("type", "none"):
		"object": return _data.get_object(_sel.cell.x, _sel.cell.y).get("params", {}).get(pname, null)
		"edge":   return _data.get_edge_params(_sel.axis, _sel.a, _sel.b).get(pname, null)
	return null

func _pick_scene(le: LineEdit, pname: String) -> void:
	_pending_scene_edit = le
	_pending_scene_param = pname
	_scene_pick_dialog.popup_centered_ratio(0.6)

func _on_scene_picked(path: String) -> void:
	if _pending_scene_edit:
		_pending_scene_edit.text = path
	_set_param(_pending_scene_param, path)
#endregion


#region Palette
func _on_layer_changed(idx: int) -> void:
	var layer := _layer_opt.get_item_id(idx)   # the canvas layer; not every one is listed, so not the index
	if _canvas:
		_canvas.active_layer = layer
	_facing_opt.disabled = not (layer == 2 or layer == 3)  # objects & spawn use facing
	_tool_opt.disabled = layer != 0                         # shape tools are floor-only
	_rebuild_palette(layer)

func _on_auto_wall() -> void:
	if _canvas == null or _data == null:
		return
	var added: int = _canvas.auto_wall()
	_status_label.text = "Auto-Wall added %d wall(s)" % added if added > 0 else "Auto-Wall: nothing to add"

func _rebuild_palette(layer: int) -> void:
	_palette.clear()
	_palette_tiles.clear()
	if _catalog == null:
		return
	var tiles: Array = []
	match layer:
		0: tiles = _catalog.floor_tiles()
		1: tiles = _catalog.edge_tiles()
		2: tiles = _catalog.object_tiles()
		3:
			_palette.add_item("Click a cell to place the spawn")
			_palette.set_item_disabled(0, true)
			return
		4:
			for line in [
					"Drag from a lever, pressure",
					"plate or wall lock onto the",
					"grate door or moving platform",
					"it should work.",
					"",
					"Puzzle: place a Lever Puzzle",
					"object, drag each lever onto",
					"it, then drag from the puzzle",
					"to the doors / platforms.",
					"",
					"Drag the same pair again to",
					"unlink. Right-click a trigger,",
					"door or platform to clear",
					"all of its links."]:
				_palette.set_item_disabled(_palette.add_item(line), true)
			return
		CanvasScript.LAYER_WEAR:
			# In GridLevelData.Wear order. Right-click puts a cell back to normal.
			_palette.add_item("Clean (no grime or damage)", _swatch(CanvasScript.WEAR_CLEAN_COLOR))
			_palette.add_item("Normal", _swatch(Color(0.31, 0.28, 0.21)))
			_palette.add_item("Heavy (mossy, cracked, wet)", _swatch(CanvasScript.WEAR_HEAVY_COLOR))
			_palette.select(_canvas.active_wear)
			return
	for t in tiles:
		var tile_icon: Texture2D = load("res://addons/level_painter/tile_icons.gd").badge(t)
		var i := _palette.add_item(t.display_name, tile_icon if tile_icon else _swatch(t.color))
		_palette_tiles.append(t)
	if _palette.item_count > 0:
		_palette.select(0)
		_on_palette_selected(0)

func _on_palette_selected(index: int) -> void:
	if _canvas.active_layer == CanvasScript.LAYER_WEAR:
		_canvas.active_wear = index
		return
	if index < 0 or index >= _palette_tiles.size():
		return
	var t: TileDef = _palette_tiles[index]
	match t.kind:
		TileDef.Kind.FLOOR:  _canvas.active_floor_id = t.id
		TileDef.Kind.EDGE:   _canvas.active_edge_id = t.id
		TileDef.Kind.OBJECT: _canvas.active_object_id = t.name_id

## Build a small solid-colour swatch texture for a palette row.
func _swatch(col: Color) -> ImageTexture:
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(col)
	return ImageTexture.create_from_image(img)
#endregion


#region File ops / floors
func _new_level(w: int, h: int) -> void:
	_dungeon = DungeonScript.new()
	_dungeon.add_floor("Floor 1", w, h)
	_res_path = ""
	_path_label.text = "(unsaved)"
	_switch_to_floor(0)

func _on_new() -> void:
	_new_level(int(_w_spin.value), int(_h_spin.value))

## Point the painter at floor i of the current dungeon and refresh everything.
func _switch_to_floor(i: int) -> void:
	if _dungeon == null or _dungeon.floor_count() == 0:
		return
	_active = clampi(i, 0, _dungeon.floor_count() - 1)
	_data = _dungeon.get_floor(_active)
	_sel = { "type": "none" }
	_w_spin.value = _data.width
	_h_spin.value = _data.height
	if _canvas:
		_canvas.setup(_data, _catalog)
	if _props_box:
		_rebuild_props()
	_refresh_floor_list()

## Rebuild the floor dropdown + name field to match the dungeon.
func _refresh_floor_list() -> void:
	if _floor_opt == null:
		return
	_floor_opt.clear()
	for i in _dungeon.floor_count():
		_floor_opt.add_item("%d: %s" % [i + 1, _dungeon.get_floor(i).level_name])
	_floor_opt.select(_active)
	_floor_name_edit.text = _dungeon.get_floor(_active).level_name

func _on_floor_selected(i: int) -> void:
	_switch_to_floor(i)

func _on_add_floor() -> void:
	_dungeon.add_floor("", int(_w_spin.value), int(_h_spin.value))
	_switch_to_floor(_dungeon.floor_count() - 1)
	_mark_dirty()

func _on_remove_floor() -> void:
	if _dungeon.floor_count() <= 1:
		_status_label.text = "A dungeon needs at least one floor."
		return
	_dungeon.remove_floor(_active)
	_switch_to_floor(mini(_active, _dungeon.floor_count() - 1))
	_mark_dirty()

func _on_floor_renamed(t: String) -> void:
	if _data == null:
		return
	_data.level_name = t
	_floor_opt.set_item_text(_active, "%d: %s" % [_active + 1, t])
	_mark_dirty()

func _mark_dirty() -> void:
	if _res_path != "":
		_path_label.text = _res_path + " *"

func _on_reload_catalog() -> void:
	_load_catalog()
	_on_layer_changed(_layer_opt.selected)
	_rebuild_props()
	_status_label.text = "Catalog reloaded"

func _on_open() -> void:
	_open_dialog.popup_centered_ratio(0.6)

func _on_open_selected(path: String) -> void:
	var dungeon: DungeonData = null
	var is_dungeon_tres := false
	if path.ends_with(".tscn"):
		# A painter-built scene carries one floor's data — open it as a 1-floor dungeon.
		var floor := _extract_data_from_scene(path)
		if floor == null:
			push_error("Level Painter: '%s' has no embedded paint data. Only painter-built .tscn files can be opened here; otherwise open the level's .tres." % path)
			return
		dungeon = DungeonScript.from_single(floor)
		_build_dialog.current_path = path
	else:
		var res = load(path)
		if res is DungeonData:
			dungeon = res
			is_dungeon_tres = true
		elif res is GridLevelData:
			dungeon = DungeonScript.from_single(res)   # legacy single-floor .tres
			is_dungeon_tres = true
		else:
			push_error("Level Painter: '%s' is not a dungeon or level. Open a .tres or a painter-built .tscn." % path)
			return
	_dungeon = dungeon
	_dungeon.ensure_ids()   # older files have no floor ids yet
	# A .tres is the editable source; a .tscn is a build target (leave unsaved).
	_res_path = path if is_dungeon_tres else ""
	_path_label.text = path
	_switch_to_floor(0)

## Pull the embedded GridLevelData out of a painter-built scene (stored as root
## meta at build time). Returns null if it isn't there.
func _extract_data_from_scene(path: String) -> GridLevelData:
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var inst = ps.instantiate()
	var data: GridLevelData = null
	if inst.has_meta(META_DATA):
		var d = inst.get_meta(META_DATA)
		if d is GridLevelData:
			data = d
	inst.free()
	return data

func _on_save() -> void:
	if _res_path == "":
		_on_save_as()
	else:
		_do_save(_res_path)

func _on_save_as() -> void:
	_save_dialog.popup_centered_ratio(0.6)

func _on_save_as_selected(path: String) -> void:
	if not path.ends_with(".tres"):
		path += ".tres"
	_do_save(path)

func _do_save(path: String) -> void:
	# Save the whole dungeon (all floors) as one DungeonData .tres.
	var e := ResourceSaver.save(_dungeon, path)
	if e == OK:
		_res_path = path
		_path_label.text = path
		_status_label.text = "Saved " + path
	else:
		push_error("Level Painter: save failed: " + error_string(e))

func _on_canvas_changed() -> void:
	_mark_dirty()
#endregion


#region Resize
func _on_resize() -> void:
	if _data == null:
		return
	_data.resize(int(_w_spin.value), int(_h_spin.value))
	_canvas.setup(_data, _catalog)
#endregion


#region Validation
func _on_validate() -> void:
	if _data == null:
		return
	var text := _validate_floors([_active])
	_status_label.text = "Validate: " + (text if text != "" else "no problems found")

## Check the given floors (indices into the dungeon), fill the Problems list, and
## return a short summary ("2 errors, 1 warning") or "" when everything is clean.
## Problems never block a build; they are there to be looked at.
func _validate_floors(indices: Array) -> String:
	_problems = []
	for i in indices:
		var floor := _dungeon.get_floor(i)
		for p in ValidatorScript.validate(_dungeon, floor, _catalog):
			p["floor"] = i
			_problems.append(p)
	_problems_list.clear()
	for p in _problems:
		var prefix := "✖ " if p.severity == ValidatorScript.ERROR else "⚠ "
		if indices.size() > 1:
			prefix += "[%s] " % _dungeon.get_floor(p.floor).level_name
		var row := _problems_list.add_item(prefix + p.text)
		_problems_list.set_item_custom_fg_color(row,
			Color(1.0, 0.45, 0.4) if p.severity == ValidatorScript.ERROR else Color(1.0, 0.82, 0.35))
	var text: String = ValidatorScript.summary(_problems)
	_problems_box.visible = not _problems.is_empty()
	_problems_title.text = "Problems — " + text
	return text

func _on_problem_selected(index: int) -> void:
	if index < 0 or index >= _problems.size():
		return
	var p: Dictionary = _problems[index]
	if p.floor != _active:
		_switch_to_floor(p.floor)
	if p.cell.x >= 0:
		_canvas.focus_cell(p.cell)

## Tail for a build's status line when validation found something.
func _problem_text(summary: String) -> String:
	return "" if summary == "" else " — %s (see Problems)" % summary
#endregion


#region Build to a playable .tscn
func _on_build() -> void:
	if _data == null:
		return
	_play_after_build = false
	_build_dialog.popup_centered_ratio(0.6)

## Rebuild the active floor in place and run it. A floor that has never been built
## has no home yet, so the first press goes through the Build dialog and plays once
## a path is chosen.
func _on_build_and_play() -> void:
	if _data == null:
		return
	if _data.built_path == "":
		_play_after_build = true
		_build_dialog.popup_centered_ratio(0.6)
		return
	_build_and_play(_data.built_path)

func _build_and_play(path: String) -> void:
	_carried = {}
	_link_warnings = []
	var problems := _validate_floors([_active])
	if not _build_floor_to(_data, path):
		_status_label.text = "Build failed for %s (see Output)" % path
		return
	_status_label.text = "Built and playing " + path + _problem_text(problems) + _carried_text() + _link_warning_text()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
		if EditorInterface.is_playing_scene():
			EditorInterface.stop_playing_scene()
		EditorInterface.play_custom_scene(path)

func _on_build_selected(path: String) -> void:
	if not path.ends_with(".tscn"):
		path += ".tscn"
	if _play_after_build:
		_play_after_build = false
		_build_and_play(path)
		return
	_carried = {}
	_link_warnings = []
	var problems := _validate_floors([_active])
	if _build_floor_to(_data, path):
		_status_label.text = "Built " + path + _problem_text(problems) + _carried_text() + _link_warning_text()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
			EditorInterface.open_scene_from_path(path)

## Build every floor of the dungeon into a chosen folder, one .tscn per floor named
## after the floor. Stair targets between floors are set by hand in each floor's
## stairs Properties (point them at these paths).
func _on_build_all() -> void:
	if _dungeon == null:
		return
	_build_all_dialog.popup_centered_ratio(0.6)

func _on_build_all_dir(dir: String) -> void:
	if not dir.ends_with("/"):
		dir += "/"
	var built := 0
	_carried = {}
	_link_warnings = []
	# Record where EVERY floor is going first, so stairs/doors on an early floor can
	# already point at a later one.
	for i in _dungeon.floor_count():
		var f := _dungeon.get_floor(i)
		f.built_path = dir + _sanitize_filename(f.level_name) + ".tscn"
	var problems := _validate_floors(range(_dungeon.floor_count()))
	for i in _dungeon.floor_count():
		var floor := _dungeon.get_floor(i)
		if _build_floor_to(floor, floor.built_path):
			built += 1
	_status_label.text = "Built %d floor(s) to %s" % [built, dir] + _problem_text(problems) + _carried_text() + _link_warning_text()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

## Build one floor's GridLevelData into a playable .tscn at `path`. Returns success.
func _build_floor_to(data: GridLevelData, path: String) -> bool:
	# The whole build (connect floors, build nodes, carry over hand wiring, apply
	# painted links, pack, save) is shared with the in-game Level Editor.
	var result: Dictionary = PipelineScript.build_floor(_dungeon, data, path, _catalog)
	for w in result.link_warnings:
		_link_warnings.append(w)
		push_warning("Level Painter: " + w)
	for key in result.carried:
		_carried[key] = int(_carried.get(key, 0)) + int(result.carried[key])
	_mark_dirty()
	if not result.ok:
		push_error("Level Painter: build failed for '%s': %s" % [path, result.error])
	return result.ok

## Status-line summary of what the last build carried over from the previous one.
func _carried_text() -> String:
	var links := int(_carried.get("links", 0))
	var nodes := int(_carried.get("nodes", 0))
	var dropped := int(_carried.get("dropped", 0))
	if links + nodes + dropped == 0:
		return ""
	var text := " — kept %d link(s), %d added node(s)" % [links, nodes]
	if dropped > 0:
		text += "; dropped %d link(s) whose object was moved or erased" % dropped
	return text

## Status-line note for floor connections that could not be fully resolved (the
## full text of each goes to the Output panel).
func _link_warning_text() -> String:
	if _link_warnings.is_empty():
		return ""
	return " — %d connection warning(s), see Output: %s" % [_link_warnings.size(), _link_warnings[0]]

## Turn a floor name into a safe file basename.
func _sanitize_filename(s: String) -> String:
	return FloorLinksScript.sanitize_filename(s)

#endregion
