@tool
extends Control

## The 2D top-down painting surface for the Level Painter. Draws a GridLevelData's
## floors (filled cells), walls/doors (thick lines ON the cell edges) and objects
## (labelled dots), and turns mouse input into edits.
##
## Layers (see LAYER_* below). EDGE painting is line-based: you click near the line
## between two cells and the nearest edge within EDGE_HIT of the cursor is painted.
## Left = paint the active tile, Right = erase. Middle-drag pans, wheel zooms toward
## the cursor. Ctrl+Z / Ctrl+Y undo/redo whole strokes.
##
## The FLOOR layer also has shape tools (see TOOL_*): drag a Rectangle of floor,
## drag a Room (floor + enclosing walls), or flood Fill an area. auto_wall() walls
## off every floor side that faces void.

signal changed   ## emitted after any edit (dock marks the resource dirty)
signal status(text: String)  ## hover/coord readout for the dock's status label
signal object_selected(cell: Vector2i)  ## an object cell was clicked (or (-1,-1) to clear)
signal edge_selected(axis: String, a: int, b: int)  ## an edge was clicked (or "",-1,-1 to clear)

const LAYER_FLOOR := 0
const LAYER_EDGE := 1
const LAYER_OBJECT := 2
const LAYER_SPAWN := 3
const LAYER_LINK := 4    ## drag from a trigger (lever, plate, lock) onto what it works
const LAYER_TEXTURE := 5 ## paint a texture onto walls that are already there
const LAYER_FLOOR_TEXTURE := 6 ## paint a texture onto floor that is already there
const LAYER_CEILING := 7 ## roof cells of floor, plain or textured

const LINK_COLOR := Color(0.35, 0.95, 1.0)
const BLUEPRINT_COLOR := Color(0.35, 0.70, 1.0)
const ICON_MIN_ZOOM := 18.0   ## pixels per cell below which objects are drawn as dots

const TOOL_BRUSH := 0
const TOOL_RECT := 1    ## drag a rectangle of floor
const TOOL_ROOM := 2    ## drag a rectangle of floor and wall its outline
const TOOL_FILL := 3    ## flood-fill floor up to walls / other floor types

const EDGE_HIT := 0.34   ## how close (in cells) to a line counts as "on the edge"
const MIN_ZOOM := 8.0
const MAX_ZOOM := 96.0

var data: GridLevelData
var catalog: TileCatalog
## Another floor drawn over this one as a blueprint (the floor below, so you can
## see what a pit trap drops onto), or null. Both floors share one grid.
var underlay: GridLevelData

var active_layer := LAYER_FLOOR
var active_floor_id := 1
var active_edge_id := 1
var active_object_id: StringName = &""
var active_facing := 0
var active_texture := ""  ## WallTextures name the Wall Textures layer paints ("" = plain)
var active_floor_texture := ""  ## ... and the one the Floor Textures layer paints
var active_ceiling_texture := ""  ## ... and the one new ceiling gets ("" = plain)
var tool := TOOL_BRUSH    ## shape tool; only applies on the FLOOR layer
var force_erase := false  ## when true, left-click erases too (Erase toggle in the dock)
## When true, clicking a cell that already holds an object SELECTS it instead of
## replacing it with the palette tile (erase first to replace). The in-game Level
## Editor turns this on; the editor dock keeps the original click-to-replace.
var select_existing := false

var zoom := 30.0          ## pixels per cell
var pan := Vector2(24, 24)

var _painting := false    ## left button held
var _erasing := false     ## right button held
var _panning := false
var _hover := {}          ## { kind, a, b } describing what a click would hit
var _stroke_axis := ""    ## "V"/"H": edge axis locked for the current drag stroke
var _dragging := false    ## a Rectangle/Room drag is in progress
var _drag_from := Vector2i.ZERO
var _drag_to := Vector2i.ZERO
var _drag_erase := false
var _focus := Vector2i(-1, -1)   ## cell ringed by focus_cell(), or (-1, -1)
var _link_from := ""      ## key of the trigger a link is being dragged from ("" = none)
var _mouse := Vector2.ZERO   ## last mouse position over the canvas

# Whole-stroke undo via layer snapshots (cheap for these grid sizes).
var _snap_before := {}
var _undo: Array = []
var _redo: Array = []
const UNDO_LIMIT := 60


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true


func setup(p_data: GridLevelData, p_catalog: TileCatalog) -> void:
	data = p_data
	catalog = p_catalog
	_undo.clear(); _redo.clear()
	queue_redraw()


func set_underlay(floor: GridLevelData) -> void:
	underlay = floor
	queue_redraw()


#region Coordinate mapping
func _grid_from_screen(p: Vector2) -> Vector2:
	return (p - pan) / zoom

func _screen_from_grid(g: Vector2) -> Vector2:
	return g * zoom + pan
#endregion


#region Input
func _gui_input(event: InputEvent) -> void:
	if data == null:
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed: _zoom_at(event.position, 1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed: _zoom_at(event.position, 1.0 / 1.1)
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_painting = true
					_begin_stroke(event.position, force_erase)
				else:
					_end_stroke()
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					_erasing = true
					_begin_stroke(event.position, true)
				else:
					_end_stroke()

	elif event is InputEventMouseMotion:
		_mouse = event.position
		if _link_from != "":
			_update_hover(event.position)
			_link_drag_status()
			return
		if _panning:
			pan += event.relative
			queue_redraw()
		else:
			_update_hover(event.position)
			if _dragging:
				_drag_to = _clamped_cell(event.position)
				emit_signal("status", "%s %d x %d" % [
					"room" if tool == TOOL_ROOM else "rectangle",
					absi(_drag_to.x - _drag_from.x) + 1, absi(_drag_to.y - _drag_from.y) + 1])
				queue_redraw()
			elif _shape_tool_active():
				pass   # Fill acts once on press; dragging does nothing more
			elif _painting:
				_apply_at(event.position, force_erase)
			elif _erasing:
				_apply_at(event.position, true)

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z and event.shift_pressed:
			redo()
		elif event.ctrl_pressed and event.keycode == KEY_Z:
			undo()
		elif event.ctrl_pressed and event.keycode == KEY_Y:
			redo()

func _zoom_at(mouse: Vector2, factor: float) -> void:
	var before := _grid_from_screen(mouse)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	pan = mouse - before * zoom   # keep the cell under the cursor fixed
	queue_redraw()

## True when the Floor layer's Rectangle / Room / Fill tool should handle input
## instead of the per-cell brush.
func _shape_tool_active() -> bool:
	return active_layer == LAYER_FLOOR and tool != TOOL_BRUSH

func _clamped_cell(pos: Vector2) -> Vector2i:
	var g := _grid_from_screen(pos)
	return Vector2i(clampi(int(floor(g.x)), 0, data.width - 1), clampi(int(floor(g.y)), 0, data.height - 1))

## Zoom and pan so the whole grid fills the canvas (with a little margin).
func fit_view() -> void:
	if data == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var margin := 28.0
	zoom = clampf(minf((size.x - margin * 2.0) / data.width, (size.y - margin * 2.0) / data.height), MIN_ZOOM, MAX_ZOOM)
	pan = (size - Vector2(data.width, data.height) * zoom) * 0.5
	queue_redraw()

## Centre the view on a cell and ring it (used by the dock's Problems list). The
## ring stays until the next paint stroke.
func focus_cell(cell: Vector2i) -> void:
	_focus = cell
	pan = size * 0.5 - (Vector2(cell) + Vector2(0.5, 0.5)) * zoom
	queue_redraw()

func _begin_stroke(pos: Vector2, erase: bool) -> void:
	_focus = Vector2i(-1, -1)
	_mouse = pos
	grab_focus()
	_stroke_axis = ""
	_snap_before = _snapshot()
	if active_layer == LAYER_LINK:
		_begin_link(pos, erase)
		return
	if not _shape_tool_active():
		_apply_at(pos, erase)
		return
	var g := _grid_from_screen(pos)
	var cell := Vector2i(int(floor(g.x)), int(floor(g.y)))
	if tool == TOOL_FILL:
		data.flood_fill(cell.x, cell.y, 0 if erase else active_floor_id)
		queue_redraw()
	else:
		_dragging = true
		_drag_erase = erase
		_drag_from = _clamped_cell(pos)
		_drag_to = _drag_from

## Commit a finished Rectangle / Room drag. Erasing clears the floor only.
func _commit_drag() -> void:
	_dragging = false
	data.fill_rect(_drag_from.x, _drag_from.y, _drag_to.x, _drag_to.y,
		0 if _drag_erase else active_floor_id)
	if tool == TOOL_ROOM and not _drag_erase:
		data.wall_rect(_drag_from.x, _drag_from.y, _drag_to.x, _drag_to.y, wall_id())
	queue_redraw()

## The edge tile the Room tool and auto_wall() build with: the Walls palette
## selection if it is a blocking wall, else the catalog's first blocking edge.
func wall_id() -> int:
	if catalog:
		var def := catalog.get_by_id(TileDef.Kind.EDGE, active_edge_id)
		if def and def.blocks:
			return def.id
		for t in catalog.edge_tiles():
			if t.blocks:
				return t.id
	return 1

## Wall off every floor side facing void, as one undoable step. Returns how many
## edges were added.
func auto_wall() -> int:
	if data == null:
		return 0
	var before := _snapshot()
	var added := data.auto_wall(wall_id())
	if added > 0:
		_push_undo(before, _snapshot())
		queue_redraw()
		emit_signal("changed")
	return added

#region Links layer
## The object or edge under the cursor, as a link key ("" if there is nothing). An
## edge wins when the cursor is on its line; otherwise the object in the cell.
func _link_key_at(pos: Vector2) -> String:
	var g := _grid_from_screen(pos)
	var vx := int(round(g.x))
	var hz := int(round(g.y))
	var cx := int(floor(g.x))
	var cz := int(floor(g.y))
	var dv := absf(g.x - vx)
	var dh := absf(g.y - hz)
	if dv <= dh and dv <= EDGE_HIT and data.get_edge_v(vx, cz) != 0:
		return data.edge_key("V", vx, cz)
	if dh < dv and dh <= EDGE_HIT and data.get_edge_h(cx, hz) != 0:
		return data.edge_key("H", cx, hz)
	if not data.get_object(cx, cz).is_empty():
		return data.object_key(cx, cz)
	return ""

func _begin_link(pos: Vector2, erase: bool) -> void:
	var key := _link_key_at(pos)
	if erase:
		if key != "":
			var removed := data.remove_links_touching(key)
			emit_signal("status", "Removed %d link(s) on %s" % [removed, LevelPaintedLinks.label_for(data, catalog, key)])
			queue_redraw()
		return
	# Links start on an object (the trigger), so prefer the cell over a nearby edge.
	var g := _grid_from_screen(pos)
	var cell_key := data.object_key(int(floor(g.x)), int(floor(g.y)))
	if LevelPaintedLinks.can_start(data, catalog, cell_key):
		_link_from = cell_key
	elif LevelPaintedLinks.can_start(data, catalog, key):
		_link_from = key
	else:
		emit_signal("status", "Start a link on a lever, pressure plate, wall lock or lever puzzle, then drag to what it works.")
	queue_redraw()

func _link_drag_status() -> void:
	var to := _link_key_at(_mouse)
	var from_label := LevelPaintedLinks.label_for(data, catalog, _link_from)
	if to == "" or to == _link_from:
		emit_signal("status", "Linking %s → drag onto one of the ringed targets" % from_label)
	elif LevelPaintedLinks.rule_for(data, catalog, _link_from, to).is_empty():
		emit_signal("status", "%s cannot be linked to %s" % [from_label, LevelPaintedLinks.label_for(data, catalog, to)])
	else:
		emit_signal("status", "%s → %s (release to %s)" % [from_label, LevelPaintedLinks.label_for(data, catalog, to),
			"unlink" if data.has_link(_link_from, to) else "link"])

func _finish_link() -> void:
	var from := _link_from
	_link_from = ""
	var to := _link_key_at(_mouse)
	if to != "" and not LevelPaintedLinks.rule_for(data, catalog, from, to).is_empty():
		var linked := data.toggle_link(from, to)
		emit_signal("status", "%s %s %s" % [LevelPaintedLinks.label_for(data, catalog, from),
			"→ now works" if linked else "no longer works", LevelPaintedLinks.label_for(data, catalog, to)])
	queue_redraw()

func _key_point(key: String) -> Vector2:
	var k := LevelPaintedLinks.parse_key(key)
	if k.is_empty():
		return Vector2.ZERO
	if k.kind == "object":
		return _screen_from_grid(Vector2(k.cell) + Vector2(0.5, 0.5))
	if k.axis == "V":
		return _screen_from_grid(Vector2(k.a, k.b + 0.5))
	return _screen_from_grid(Vector2(k.a + 0.5, k.b))

func _draw_arrow(from: Vector2, to: Vector2, col: Color, width: float) -> void:
	draw_line(from, to, col, width, true)
	var dir := (to - from).normalized()
	if dir == Vector2.ZERO:
		return
	var head := maxf(8.0, zoom * 0.3)
	var side := Vector2(-dir.y, dir.x) * head * 0.5
	draw_colored_polygon(PackedVector2Array([to, to - dir * head + side, to - dir * head - side]), col)

## Painted links as arrows from trigger to target: bright on the Links layer, a
## faint reminder on the others. While dragging, everything the trigger could be
## linked to is ringed.
func _draw_links() -> void:
	var on_layer := active_layer == LAYER_LINK
	var col := Color(LINK_COLOR, 0.95 if on_layer else 0.3)
	var width := maxf(2.0, zoom * 0.08) if on_layer else 1.5
	for link in LevelPaintedLinks.valid_links(data, catalog):
		_draw_arrow(_key_point(link.from), _key_point(link.to), col, width)

	if _link_from == "":
		return
	var src := LevelPaintedLinks.tile_at(data, catalog, _link_from)
	if src != null:
		var ring := Color(LINK_COLOR, 0.9)
		for cell in data.objects:
			var key := data.object_key(cell.x, cell.y)
			if not LevelPaintedLinks.rule_for(data, catalog, _link_from, key).is_empty():
				draw_arc(_key_point(key), zoom * 0.42, 0.0, TAU, 28, ring, 2.0)
		for z in data.height:
			for x in range(data.width + 1):
				_ring_edge_target("V", x, z, ring)
		for z in range(data.height + 1):
			for x in data.width:
				_ring_edge_target("H", x, z, ring)
	_draw_arrow(_key_point(_link_from), _mouse, Color(1, 1, 1, 0.9), maxf(2.0, zoom * 0.08))

func _ring_edge_target(axis: String, a: int, b: int, col: Color) -> void:
	if (data.get_edge_v(a, b) if axis == "V" else data.get_edge_h(a, b)) == 0:
		return
	var key := data.edge_key(axis, a, b)
	if not LevelPaintedLinks.rule_for(data, catalog, _link_from, key).is_empty():
		draw_arc(_key_point(key), zoom * 0.3, 0.0, TAU, 24, col, 2.0)
#endregion

func _end_stroke() -> void:
	if _link_from != "":
		_finish_link()
	if _dragging:
		_commit_drag()
	if _painting or _erasing:
		_painting = false
		_erasing = false
		_stroke_axis = ""
		_push_undo(_snap_before, _snapshot())
		emit_signal("changed")
#endregion


#region Hit-testing / applying
## Work out what the cursor is over: a cell, a vertical edge, or a horizontal edge.
func _target_at(pos: Vector2) -> Dictionary:
	var g := _grid_from_screen(pos)
	var cx := int(floor(g.x))
	var cz := int(floor(g.y))
	if active_layer == LAYER_EDGE or active_layer == LAYER_TEXTURE:
		# Distance to the nearest vertical line (integer gx) and horizontal line.
		var vx := int(round(g.x))
		var hz := int(round(g.y))
		var dv := absf(g.x - vx)
		var dh := absf(g.y - hz)
		# Once a drag has committed to an axis, stay on it so wobbling across a wall
		# doesn't paint stray perpendicular edges. First click / hover is unlocked.
		var lock := _stroke_axis if (_painting or _erasing) else ""
		if lock == "V":
			return { "kind": "vedge", "a": vx, "b": cz } if dv <= EDGE_HIT else {}
		if lock == "H":
			return { "kind": "hedge", "a": cx, "b": hz } if dh <= EDGE_HIT else {}
		if dv <= dh and dv <= EDGE_HIT:
			return { "kind": "vedge", "a": vx, "b": cz }   # edges_v(vx, cz)
		elif dh < dv and dh <= EDGE_HIT:
			return { "kind": "hedge", "a": cx, "b": hz }   # edges_h(cx, hz)
		return {}
	return { "kind": "cell", "a": cx, "b": cz }

func _update_hover(pos: Vector2) -> void:
	_hover = _target_at(pos)
	queue_redraw()
	_emit_status(pos)

func _apply_at(pos: Vector2, erase: bool) -> void:
	var t := _target_at(pos)
	if t.is_empty():
		return
	match t.kind:
		"cell":
			var x: int = t.a
			var z: int = t.b
			if not data.in_bounds(x, z):
				return
			match active_layer:
				LAYER_FLOOR:
					data.set_floor(x, z, 0 if erase else active_floor_id)
				LAYER_FLOOR_TEXTURE:
					data.set_floor_texture(x, z, "" if erase else active_floor_texture)
				LAYER_CEILING:
					if erase:
						data.erase_ceiling(x, z)
					else:
						data.set_ceiling(x, z, active_ceiling_texture)
				LAYER_OBJECT:
					if erase:
						data.erase_object(x, z)
						emit_signal("object_selected", Vector2i(-1, -1))
					elif select_existing and not data.get_object(x, z).is_empty():
						emit_signal("object_selected", Vector2i(x, z))   # select, don't overwrite
					elif active_object_id != &"":
						data.set_object(x, z, active_object_id, active_facing)
						emit_signal("object_selected", Vector2i(x, z))
				LAYER_SPAWN:
					if not erase:
						data.spawn_cell = Vector2i(x, z)
						data.spawn_facing = active_facing
		"vedge":
			_stroke_axis = "V"   # lock this drag to vertical edges
			if active_layer == LAYER_TEXTURE:
				_paint_texture("V", t.a, t.b, erase)
				queue_redraw()
				return
			data.set_edge_v(t.a, t.b, 0 if erase else active_edge_id)
			emit_signal("edge_selected", "", -1, -1) if erase else emit_signal("edge_selected", "V", t.a, t.b)
		"hedge":
			_stroke_axis = "H"   # lock this drag to horizontal edges
			if active_layer == LAYER_TEXTURE:
				_paint_texture("H", t.a, t.b, erase)
				queue_redraw()
				return
			data.set_edge_h(t.a, t.b, 0 if erase else active_edge_id)
			emit_signal("edge_selected", "", -1, -1) if erase else emit_signal("edge_selected", "H", t.a, t.b)
	queue_redraw()
#endregion


#region Wall textures
## Can the edge take a texture? Only solid wall does: a plain wall, or the wall a
## door is set into.
func is_texturable(axis: String, a: int, b: int) -> bool:
	var id := data.get_edge_v(a, b) if axis == "V" else data.get_edge_h(a, b)
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id) if catalog else null
	return def != null and (def.blocks or def.wall_backed)

func _paint_texture(axis: String, a: int, b: int, erase: bool) -> void:
	if is_texturable(axis, a, b):
		_set_texture(axis, a, b, "" if erase else active_texture)

func _set_texture(axis: String, a: int, b: int, texture: String) -> void:
	if String(data.get_edge_params(axis, a, b).get(WallTextures.PARAM, "")) != texture:
		data.set_edge_param(axis, a, b, WallTextures.PARAM, texture)

## Give every texturable wall on the floor `texture`, as one undoable step.
## Returns how many walls changed.
func texture_all_walls(texture: String) -> int:
	if data == null:
		return 0
	var before := _snapshot()
	var count := 0
	for z in data.height:
		for x in range(data.width + 1):
			count += _retexture("V", x, z, texture)
	for z in range(data.height + 1):
		for x in data.width:
			count += _retexture("H", x, z, texture)
	if count > 0:
		_push_undo(before, _snapshot())
		queue_redraw()
		emit_signal("changed")
	return count

## Give every floor cell `texture`, as one undoable step. Returns how many changed.
func texture_all_floors(texture: String) -> int:
	if data == null:
		return 0
	var before := _snapshot()
	var count := 0
	for z in data.height:
		for x in data.width:
			if data.get_floor(x, z) != 0 and data.get_floor_texture(x, z) != texture:
				data.set_floor_texture(x, z, texture)
				count += 1
	if count > 0:
		_push_undo(before, _snapshot())
		queue_redraw()
		emit_signal("changed")
	return count

## Roof every floor cell with `texture`, as one undoable step. Returns how many
## cells changed.
func ceiling_all_floors(texture: String) -> int:
	if data == null:
		return 0
	var before := _snapshot()
	var count := 0
	for z in data.height:
		for x in data.width:
			if data.get_floor(x, z) != 0 and not (data.has_ceiling(x, z) and data.get_ceiling(x, z) == texture):
				data.set_ceiling(x, z, texture)
				count += 1
	if count > 0:
		_push_undo(before, _snapshot())
		queue_redraw()
		emit_signal("changed")
	return count

## Take every ceiling off the floor, as one undoable step. Returns how many went.
func clear_ceilings() -> int:
	if data == null or data.ceilings.is_empty():
		return 0
	var before := _snapshot()
	var count := data.ceilings.size()
	data.ceilings = {}
	_push_undo(before, _snapshot())
	queue_redraw()
	emit_signal("changed")
	return count

func _retexture(axis: String, a: int, b: int, texture: String) -> int:
	if not is_texturable(axis, a, b) \
			or String(data.get_edge_params(axis, a, b).get(WallTextures.PARAM, "")) == texture:
		return 0
	_set_texture(axis, a, b, texture)
	return 1
#endregion


#region Undo
func _snapshot() -> Dictionary:
	return {
		"floors": data.floors.duplicate(),
		"floor_textures": data.floor_textures.duplicate(),
		"ceilings": data.ceilings.duplicate(),
		"edges_v": data.edges_v.duplicate(),
		"edges_h": data.edges_h.duplicate(),
		"objects": data.objects.duplicate(true),
		"links": data.links.duplicate(true),
		"edge_params": data.edge_params.duplicate(true),
		"spawn_cell": data.spawn_cell,
		"spawn_facing": data.spawn_facing,
	}

func _restore(s: Dictionary) -> void:
	data.floors = s.floors.duplicate()
	data.floor_textures = s.floor_textures.duplicate()
	data.ceilings = s.ceilings.duplicate()
	data.edges_v = s.edges_v.duplicate()
	data.edges_h = s.edges_h.duplicate()
	data.objects = s.objects.duplicate(true)
	data.links.assign(s.links.duplicate(true))
	data.edge_params = s.edge_params.duplicate(true)
	data.spawn_cell = s.spawn_cell
	data.spawn_facing = s.spawn_facing
	queue_redraw()
	emit_signal("changed")

func _push_undo(before: Dictionary, after: Dictionary) -> void:
	# Skip no-op strokes (e.g. a click that hit nothing paintable).
	if _snapshots_equal(before, after):
		return
	_undo.append({ "before": before, "after": after })
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_redo.clear()

func _snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	return a.floors == b.floors and a.floor_textures == b.floor_textures and a.ceilings == b.ceilings and a.edges_v == b.edges_v and a.edges_h == b.edges_h \
		and a.objects == b.objects and a.links == b.links and a.edge_params == b.edge_params \
		and a.spawn_cell == b.spawn_cell and a.spawn_facing == b.spawn_facing

func undo() -> void:
	if _undo.is_empty():
		return
	var e: Dictionary = _undo.pop_back()
	_restore(e.before)
	_redo.append(e)

func redo() -> void:
	if _redo.is_empty():
		return
	var e: Dictionary = _redo.pop_back()
	_restore(e.after)
	_undo.append(e)
#endregion


#region Drawing
func _draw() -> void:
	var bg := Color(0.12, 0.12, 0.14)
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	if data == null:
		draw_string(ThemeDB.fallback_font, Vector2(16, 28),
			"New or Open a level to start painting.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(0.7, 0.7, 0.7))
		return

	_draw_floors()
	_draw_grid_lines()
	_draw_underlay()
	_draw_edges()
	_draw_objects()
	_draw_spawn()
	_draw_links()
	_draw_hover()
	_draw_drag()
	if _focus.x >= 0:
		var centre := _screen_from_grid(Vector2(_focus) + Vector2(0.5, 0.5))
		draw_arc(centre, zoom * 0.75, 0.0, TAU, 40, Color(1.0, 0.85, 0.2), maxf(2.5, zoom * 0.1))

func _draw_floors() -> void:
	for z in data.height:
		for x in data.width:
			var id := data.get_floor(x, z)
			if id == 0:
				continue
			var def := catalog.get_by_id(TileDef.Kind.FLOOR, id) if catalog else null
			var col := (def.color if def else Color(0.6, 0.55, 0.42))
			# Textured floor takes its texture's colour (a pit stays visibly darker);
			# on the Floor Textures layer, floor still plain is dimmed.
			var texture := data.get_floor_texture(x, z)
			if texture != "":
				col = WallTextures.color(texture)
				if def and def.y_offset < 0.0:
					col = col.darkened(0.55)
			elif active_layer == LAYER_FLOOR_TEXTURE:
				col = col.darkened(0.45)
			# The Ceilings layer looks at the roof instead: roofed cells in their
			# ceiling's colour, open floor dimmed beneath.
			if active_layer == LAYER_CEILING:
				if data.has_ceiling(x, z):
					var roof := data.get_ceiling(x, z)
					col = WallTextures.color(roof) if roof != "" else Color(0.47, 0.42, 0.37)
				else:
					col = (def.color if def else Color(0.6, 0.55, 0.42)).darkened(0.6)
			var tl := _screen_from_grid(Vector2(x, z))
			draw_rect(Rect2(tl, Vector2(zoom, zoom)), col)
			# On the other layers a roofed cell just carries a small corner tab.
			if active_layer != LAYER_CEILING and data.has_ceiling(x, z):
				var tab := zoom * 0.28
				draw_colored_polygon(PackedVector2Array([tl, tl + Vector2(tab, 0), tl + Vector2(0, tab)]),
					Color(0.1, 0.08, 0.06, 0.75))

func _draw_grid_lines() -> void:
	var line := Color(1, 1, 1, 0.10)
	for x in range(data.width + 1):
		var a := _screen_from_grid(Vector2(x, 0))
		var b := _screen_from_grid(Vector2(x, data.height))
		draw_line(a, b, line, 1.0)
	for z in range(data.height + 1):
		var a := _screen_from_grid(Vector2(0, z))
		var b := _screen_from_grid(Vector2(data.width, z))
		draw_line(a, b, line, 1.0)

## The blueprint of the floor below: its floor as a faint wash, its walls and
## doors as dashed lines, its objects as small rings. Drawn over this floor's cells
## (and beyond its bounds, if the floor below is bigger) but under its own walls.
func _draw_underlay() -> void:
	if underlay == null:
		return
	var wash := Color(BLUEPRINT_COLOR, 0.16)
	var line := Color(BLUEPRINT_COLOR, 0.85)
	var width := maxf(1.5, zoom * 0.05)
	var dash := maxf(3.0, zoom * 0.16)
	var inset := zoom * 0.12
	for z in underlay.height:
		for x in underlay.width:
			if underlay.get_floor(x, z) != 0:
				draw_rect(Rect2(_screen_from_grid(Vector2(x, z)) + Vector2(inset, inset),
					Vector2(zoom, zoom) - Vector2(inset, inset) * 2.0), wash)
	for z in underlay.height:
		for ex in range(underlay.width + 1):
			if underlay.get_edge_v(ex, z) != 0:
				draw_dashed_line(_screen_from_grid(Vector2(ex, z)), _screen_from_grid(Vector2(ex, z + 1)), line, width, dash)
	for ez in range(underlay.height + 1):
		for x in underlay.width:
			if underlay.get_edge_h(x, ez) != 0:
				draw_dashed_line(_screen_from_grid(Vector2(x, ez)), _screen_from_grid(Vector2(x + 1, ez)), line, width, dash)
	for cell in underlay.objects:
		draw_arc(_screen_from_grid(Vector2(cell) + Vector2(0.5, 0.5)), zoom * 0.36, 0.0, TAU, 20, line, width)

func _draw_edges() -> void:
	var w := maxf(3.0, zoom * 0.14)
	# Vertical edges.
	for z in data.height:
		for ex in range(data.width + 1):
			var id := data.get_edge_v(ex, z)
			if id != 0:
				var a := _screen_from_grid(Vector2(ex, z))
				var b := _screen_from_grid(Vector2(ex, z + 1))
				draw_line(a, b, _edge_draw_color(id, "V", ex, z), w)
				_draw_edge_icon(id, (a + b) * 0.5)
	# Horizontal edges.
	for ez in range(data.height + 1):
		for x in data.width:
			var id := data.get_edge_h(x, ez)
			if id != 0:
				var a := _screen_from_grid(Vector2(x, ez))
				var b := _screen_from_grid(Vector2(x + 1, ez))
				draw_line(a, b, _edge_draw_color(id, "H", x, ez), w)
				_draw_edge_icon(id, (a + b) * 0.5)

## Doors (anything on an edge that is not plain wall) carry their picture, so a
## stone door and a grate can be told apart at a glance.
func _draw_edge_icon(id: int, at: Vector2) -> void:
	if zoom < ICON_MIN_ZOOM:
		return
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id) if catalog else null
	if def == null or (def.blocks and not def.wall_backed):
		return
	var icon := LevelTileIcons.icon(def)
	if icon:
		var side := zoom * 0.5
		draw_circle(at, side * 0.58, Color(LevelTileIcons.BADGE_COLOR, 0.95))
		draw_texture_rect(icon, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), false)

## An edge's colour on the map. A wall with a painted texture takes that texture's
## colour; on the Wall Textures layer, walls still plain are dimmed so the painted
## ones stand out.
func _edge_draw_color(id: int, axis: String, a: int, b: int) -> Color:
	var texture := String(data.get_edge_params(axis, a, b).get(WallTextures.PARAM, ""))
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id) if catalog else null
	if texture != "" and def != null and def.blocks:
		return WallTextures.color(texture)
	if active_layer == LAYER_TEXTURE and texture == "":
		return Color(_edge_color(id), 0.45)
	return _edge_color(id)

func _edge_color(id: int) -> Color:
	var def := catalog.get_by_id(TileDef.Kind.EDGE, id) if catalog else null
	return (def.color if def else Color(0.6, 0.55, 0.45))

func _draw_objects() -> void:
	for key in data.objects:
		var entry: Dictionary = data.objects[key]
		var def := catalog.get_object(entry.get("id", &"")) if catalog else null
		var col := (def.color if def else Color.WHITE)
		var c := _screen_from_grid(Vector2(key.x + 0.5, key.y + 0.5))
		var dir := _facing_vec(entry.get("facing", 0))
		# Its picture on a disc of its colour, with a small arrow for the facing;
		# zoomed far out (or with no picture) it is the plain dot.
		var icon := LevelTileIcons.icon(def) if zoom >= ICON_MIN_ZOOM else null
		if icon:
			draw_circle(c, zoom * 0.45, Color(col, 0.3))
			var side := zoom * 0.8
			draw_texture_rect(icon, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
			var tip := c + dir * zoom * 0.48
			var perp := Vector2(-dir.y, dir.x) * zoom * 0.09
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * zoom * 0.14 + perp, tip - dir * zoom * 0.14 - perp]), col)
			continue
		draw_circle(c, zoom * 0.28, col)
		# Facing tick.
		draw_line(c, c + dir * zoom * 0.4, col, maxf(2.0, zoom * 0.06))
		if def and zoom >= 18:
			var tag := _initials(def.display_name)
			draw_string(ThemeDB.fallback_font, c + Vector2(-4.0 * tag.length(), 5),
				tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)

## Two-letter tag for an object dot: word initials ("Push Block" -> "PB"), or the
## first two letters of a one-word name ("Lever" -> "Le").
func _initials(display_name: String) -> String:
	var words := display_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return display_name.substr(0, 2)

func _draw_spawn() -> void:
	if data.spawn_cell.x < 0:
		return
	var c := _screen_from_grid(Vector2(data.spawn_cell.x + 0.5, data.spawn_cell.y + 0.5))
	var col := Color(0.3, 1.0, 0.4)
	var r := zoom * 0.34
	var dir := _facing_vec(data.spawn_facing)
	var perp := Vector2(-dir.y, dir.x)
	# Little triangle pointing the spawn facing.
	var pts := PackedVector2Array([c + dir * r, c - dir * r * 0.7 + perp * r * 0.7,
		c - dir * r * 0.7 - perp * r * 0.7])
	draw_colored_polygon(pts, col)

func _draw_hover() -> void:
	if _hover.is_empty():
		return
	var hi := Color(1, 1, 1, 0.5)
	match _hover.kind:
		"cell":
			var tl := _screen_from_grid(Vector2(_hover.a, _hover.b))
			draw_rect(Rect2(tl, Vector2(zoom, zoom)), Color(1, 1, 1, 0.18))
			draw_rect(Rect2(tl, Vector2(zoom, zoom)), hi, false, 2.0)
		"vedge":
			var a := _screen_from_grid(Vector2(_hover.a, _hover.b))
			var b := _screen_from_grid(Vector2(_hover.a, _hover.b + 1))
			draw_line(a, b, hi, maxf(3.0, zoom * 0.16))
		"hedge":
			var a := _screen_from_grid(Vector2(_hover.a, _hover.b))
			var b := _screen_from_grid(Vector2(_hover.a + 1, _hover.b))
			draw_line(a, b, hi, maxf(3.0, zoom * 0.16))

## Preview of an in-progress Rectangle / Room drag.
func _draw_drag() -> void:
	if not _dragging:
		return
	var lo := Vector2(mini(_drag_from.x, _drag_to.x), mini(_drag_from.y, _drag_to.y))
	var hi := Vector2(maxi(_drag_from.x, _drag_to.x) + 1, maxi(_drag_from.y, _drag_to.y) + 1)
	var rect := Rect2(_screen_from_grid(lo), (hi - lo) * zoom)
	if _drag_erase:
		draw_rect(rect, Color(1.0, 0.3, 0.3, 0.25))
		draw_rect(rect, Color(1.0, 0.4, 0.4, 0.9), false, 2.0)
		return
	var def := catalog.get_by_id(TileDef.Kind.FLOOR, active_floor_id) if catalog else null
	var fill := def.color if def else Color(0.6, 0.55, 0.42)
	draw_rect(rect, Color(fill, 0.45))
	if tool == TOOL_ROOM:
		draw_rect(rect, _edge_color(wall_id()), false, maxf(3.0, zoom * 0.14))
	else:
		draw_rect(rect, Color(1, 1, 1, 0.8), false, 2.0)

func _facing_vec(facing: int) -> Vector2:
	# Canvas is top-down: North = up (-Y on screen), matching world -Z.
	match facing:
		GridLevelData.Facing.NORTH: return Vector2(0, -1)
		GridLevelData.Facing.EAST:  return Vector2(1, 0)
		GridLevelData.Facing.SOUTH: return Vector2(0, 1)
		GridLevelData.Facing.WEST:  return Vector2(-1, 0)
	return Vector2(0, -1)
#endregion


func _emit_status(pos: Vector2) -> void:
	if _hover.is_empty():
		emit_signal("status", "")
		return
	match _hover.kind:
		"cell": emit_signal("status", "cell (%d, %d)%s%s" % [_hover.a, _hover.b, _floor_texture_note(), _below_note()])
		"vedge": emit_signal("status", "vertical edge x=%d z=%d%s" % [_hover.a, _hover.b, _texture_note("V")])
		"hedge": emit_signal("status", "horizontal edge x=%d z=%d%s" % [_hover.a, _hover.b, _texture_note("H")])

## With a blueprint showing, what lies under the hovered cell on the floor below.
func _below_note() -> String:
	if underlay == null:
		return ""
	if underlay.get_floor(_hover.a, _hover.b) == 0:
		return "  -  below: nothing"
	var entry := underlay.get_object(_hover.a, _hover.b)
	var def := catalog.get_object(entry.get("id", &"")) if catalog and not entry.is_empty() else null
	return "  -  below: " + (def.display_name if def else "floor")

## On the Floor Textures / Ceilings layers, what the hovered cell is wearing.
func _floor_texture_note() -> String:
	if active_layer == LAYER_CEILING:
		if data.get_floor(_hover.a, _hover.b) == 0:
			return "  -  no floor here to roof"
		if not data.has_ceiling(_hover.a, _hover.b):
			return "  -  open to the sky"
		var roof := data.get_ceiling(_hover.a, _hover.b)
		return "  -  ceiling: " + (WallTextures.label(roof) if roof != "" else "plain")
	if active_layer != LAYER_FLOOR_TEXTURE:
		return ""
	if data.get_floor(_hover.a, _hover.b) == 0:
		return "  -  no floor here to paint"
	var texture := data.get_floor_texture(_hover.a, _hover.b)
	return "  -  " + (WallTextures.label(texture) if texture != "" else "plain floor")

## On the Wall Textures layer, what the hovered wall is wearing.
func _texture_note(axis: String) -> String:
	if active_layer != LAYER_TEXTURE:
		return ""
	if not is_texturable(axis, _hover.a, _hover.b):
		return "  -  no wall here to paint"
	var texture := String(data.get_edge_params(axis, _hover.a, _hover.b).get(WallTextures.PARAM, ""))
	return "  -  " + (WallTextures.label(texture) if texture != "" else "plain wall")
