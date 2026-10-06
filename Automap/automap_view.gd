extends Control
class_name AutomapView

## Draws the explored map from AutomapManager as a flat, north-up floor plan on a
## procedural parchment sheet (automap_parchment.gdshader): lightly washed floor
## tiles, sepia wall lines with cross-hatched rock behind them, doors, an icon for
## each marked object (drawn where it is right now, so push blocks, platforms and
## fireballs move on the map), and an arrow for the party. `expand` blends between the minimap framing (fixed
## scale, centred on the party) and the full-map framing (everything explored,
## scaled to fit `large_size`).

const PARCHMENT_SHADER := preload("res://Automap/automap_parchment.gdshader")

const MINI_CELL_PX := 16.0
const LARGE_CELL_MIN := 8.0
const LARGE_CELL_MAX := 34.0
const LARGE_PADDING := 64.0          # parchment margin kept clear around the full map

const FLOOR := Color(0.95, 0.92, 0.82, 0.38)        # a light wash; the paper shows through
const GRID_LINE := Color(0.5, 0.31, 0.15, 0.32)
const INK := Color(0.43, 0.24, 0.1)                 # sepia
const DOOR_FILL := Color(0.92, 0.87, 0.75)
const CHEST_FILL := Color(0.74, 0.55, 0.3)
const PARTY := Color(0.5, 0.1, 0.07)
const PIT_FILL := Color(0.2, 0.12, 0.07, 0.8)
const STONE_FILL := Color(0.66, 0.6, 0.5)           # push blocks, platforms
const DRAGON_FILL := Color(0.58, 0.2, 0.1)
const FIRE_OUTER := Color(0.9, 0.36, 0.08)
const FIRE_CORE := Color(1.0, 0.86, 0.42)
const HATCH_ALPHA := 0.75

# The diagonal neighbour beyond each corner, and the two walls that make it a
# walled (convex) corner.
const CORNERS := [
	[Vector2i(1, -1), AutomapManager.WALL_N | AutomapManager.WALL_E],
	[Vector2i(1, 1), AutomapManager.WALL_S | AutomapManager.WALL_E],
	[Vector2i(-1, 1), AutomapManager.WALL_S | AutomapManager.WALL_W],
	[Vector2i(-1, -1), AutomapManager.WALL_N | AutomapManager.WALL_W]]

var expand := 0.0:
	set(value):
		expand = value
		queue_redraw()
# The control's size when fully enlarged, so the full-map scale stays steady
# while the panel is still growing towards it.
var large_size := Vector2.ZERO

var _parchment: ColorRect
var _last_pose := Vector3.INF

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_parchment()
	AutomapManager.map_changed.connect(queue_redraw)
	resized.connect(_on_resized)

# The sheet the map is drawn on: a shader-filled rect behind this control's own
# drawing.
func _build_parchment() -> void:
	_parchment = ColorRect.new()
	_parchment.show_behind_parent = true
	_parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = PARCHMENT_SHADER
	_parchment.material = mat
	add_child(_parchment)
	_parchment.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_on_resized()

func _on_resized() -> void:
	(_parchment.material as ShaderMaterial).set_shader_parameter("rect_size", size)
	queue_redraw()

func _process(_delta: float) -> void:
	# Redraw only when something on the map can have changed: a mark that moves,
	# or the party moving or turning.
	if AutomapManager.has_moving_marks:
		queue_redraw()
		return
	var player := AutomapManager.get_player()
	if player == null or not player.is_inside_tree():
		return
	var pose := Vector3(player.global_position.x, player.global_position.z, player.global_rotation.y)
	if not pose.is_equal_approx(_last_pose):
		_last_pose = pose
		queue_redraw()

func _draw() -> void:
	var player := AutomapManager.get_player()
	var has_player := player != null and player.is_inside_tree()
	var party_cell := Vector2.ZERO   # fractional, so the minimap scrolls smoothly mid-step
	if has_player:
		party_cell = Vector2(player.global_position.x, player.global_position.z) / AutomapManager.GRID_SIZE

	var cell_px := MINI_CELL_PX
	var focus := party_cell
	if expand > 0.0:
		var bounds := AutomapManager.get_bounds()
		var room := (large_size if large_size != Vector2.ZERO else size) - Vector2.ONE * LARGE_PADDING * 2.0
		var fit := clampf(minf(room.x / bounds.size.x, room.y / bounds.size.y), LARGE_CELL_MIN, LARGE_CELL_MAX)
		var middle := Vector2(bounds.position) + Vector2(bounds.size) * 0.5 - Vector2(0.5, 0.5)
		cell_px = lerpf(MINI_CELL_PX, fit, expand)
		focus = party_cell.lerp(middle, expand)

	# Screen position of the centre of cell (0, 0).
	var origin := size * 0.5 - focus * cell_px
	var half := Vector2.ONE * cell_px * 0.5
	var visible_rect := Rect2(Vector2.ZERO, size).grow(cell_px)
	var cells: Dictionary = AutomapManager.cells

	var shown: Array[Vector2i] = []
	for cell in cells:
		if visible_rect.has_point(origin + Vector2(cell) * cell_px):
			shown.append(cell)

	# Hatched rock goes down first, then floor tiles, then the ink on top so wall
	# lines are never painted over.
	for cell in _rock_cells(shown, cells):
		_draw_hatching(origin + Vector2(cell) * cell_px, cell_px)

	for cell in shown:
		var tile := Rect2(origin + Vector2(cell) * cell_px - half, half * 2.0)
		draw_rect(tile, FLOOR)
		draw_rect(tile, GRID_LINE, false, 1.0)
		if cells[cell] & AutomapManager.PIT:
			_draw_pit(tile.get_center(), cell_px)

	var wall_px := maxf(2.0, cell_px * 0.14)
	for cell in shown:
		var mask: int = cells[cell]
		if mask == 0:
			continue
		var c := origin + Vector2(cell) * cell_px
		var h := cell_px * 0.5
		var cap := wall_px * 0.5   # overshoot so corners meet square
		if mask & AutomapManager.WALL_N:
			draw_line(c + Vector2(-h - cap, -h), c + Vector2(h + cap, -h), INK, wall_px)
		if mask & AutomapManager.WALL_S:
			draw_line(c + Vector2(-h - cap, h), c + Vector2(h + cap, h), INK, wall_px)
		if mask & AutomapManager.WALL_W:
			draw_line(c + Vector2(-h, -h - cap), c + Vector2(-h, h + cap), INK, wall_px)
		if mask & AutomapManager.WALL_E:
			draw_line(c + Vector2(h, -h - cap), c + Vector2(h, h + cap), INK, wall_px)

	_draw_doors(origin, cell_px, cells)

	_draw_marks(origin, cell_px, cells)

	if has_player:
		_draw_party(origin + party_cell * cell_px, player.global_rotation.y, cell_px)

# Solid rock bordering the explored floor: the cell across each wall, plus the
# cell diagonally beyond a walled corner so the hatching wraps around it. A wall
# with explored floor on both sides has no rock to hatch.
func _rock_cells(shown: Array[Vector2i], cells: Dictionary) -> Dictionary:
	var rock: Dictionary = {}
	for cell in shown:
		var mask: int = cells[cell]
		if mask == 0:
			continue
		for side in AutomapManager.SIDES:
			if mask & side[1] and not cells.has(cell + side[0]):
				rock[cell + side[0]] = true
		for corner in CORNERS:
			if mask & corner[1] == corner[1] and not cells.has(cell + corner[0]):
				rock[cell + corner[0]] = true
	return rock

# Fill a rock cell with a diagonal cross-hatch: evenly spaced pen lines slanting
# both ways. The spacing divides the cell exactly, so the mesh runs unbroken from
# one rock cell into the next.
func _draw_hatching(center: Vector2, cell_px: float) -> void:
	var color := Color(INK, HATCH_ALPHA)
	var lines := 5 if cell_px >= 20.0 else 3   # per cell, each way
	var h := 0.5
	for k in range(-lines + 1, lines):
		var c := float(k) / lines
		var u0 := maxf(-h, c - h)
		var u1 := minf(h, c + h)
		# One line of each slant: u + v = c and u - v = c (cell units from the centre).
		draw_line(center + Vector2(u0, c - u0) * cell_px, center + Vector2(u1, c - u1) * cell_px, color, 1.0, true)
		draw_line(center + Vector2(u0, u0 - c) * cell_px, center + Vector2(u1, u1 - c) * cell_px, color, 1.0, true)

# A door is a pale lozenge sitting across its edge, shown once either cell beside
# it has been explored.
func _draw_doors(origin: Vector2, cell_px: float, cells: Dictionary) -> void:
	for key in AutomapManager.doors:
		var across_x: bool = key.x % 2 != 0   # joins two cells side by side
		var step := Vector2i(1, 0) if across_x else Vector2i(0, 1)
		if not (cells.has((key - step) / 2) or cells.has((key + step) / 2)):
			continue
		var mid := origin + Vector2(key) * 0.5 * cell_px
		# The wall the door is set in runs the full edge; the lozenge sits on it.
		var run := (Vector2(0.0, 0.5) if across_x else Vector2(0.5, 0.0)) * cell_px
		draw_line(mid - run, mid + run, INK, maxf(2.0, cell_px * 0.14))
		var along := cell_px * 0.5
		var thick := cell_px * 0.26
		var door_size := Vector2(thick, along) if across_x else Vector2(along, thick)
		var rect := Rect2(mid - door_size * 0.5, door_size)
		draw_rect(rect, DOOR_FILL)
		draw_rect(rect, INK, false, maxf(1.0, cell_px * 0.07))

# A pit: a dark hole with a pale rim of floor left around it.
func _draw_pit(center: Vector2, cell_px: float) -> void:
	var hole := Rect2(center - Vector2.ONE * cell_px * 0.36, Vector2.ONE * cell_px * 0.72)
	draw_rect(hole, PIT_FILL)
	draw_rect(hole, INK, false, maxf(1.0, cell_px * 0.07))

# Every marked object standing on explored floor, at its live position. Fixed
# things snap to their cell; wall-mounted ones keep their place against the wall;
# movers glide. Fireballs go on last so they pass over everything else.
func _draw_marks(origin: Vector2, cell_px: float, cells: Dictionary) -> void:
	var visible_rect := Rect2(Vector2.ZERO, size).grow(cell_px)
	var dragons: Array[Node3D] = []
	for mark in AutomapManager.marks:
		var node = mark["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var type: String = mark["type"]
		var cell := AutomapManager.world_to_cell(node.global_position)
		if not cells.has(cell):
			continue
		var cell_center := origin + Vector2(cell) * cell_px
		var center := cell_center
		if type in [AutomapManager.MARK_LEVER, AutomapManager.MARK_LOCK,
				AutomapManager.MARK_PUSH_BLOCK, AutomapManager.MARK_PLATFORM]:
			center = origin + _map_pos(node.global_position) * cell_px
		if not visible_rect.has_point(center):
			continue
		_draw_mark(type, center, cell_px, node, cell_center)
		if type == AutomapManager.MARK_DRAGON:
			dragons.append(node)
	for trap in dragons:
		_draw_fireball(trap, origin, cell_px, cells)

# World position -> fractional map cell.
func _map_pos(world_pos: Vector3) -> Vector2:
	return Vector2(world_pos.x, world_pos.z) / AutomapManager.GRID_SIZE

func _draw_mark(type: String, center: Vector2, cell_px: float, node: Node3D, cell_center: Vector2) -> void:
	var line_px := maxf(1.0, cell_px * 0.08)
	var u := cell_px   # icon unit: one cell
	match type:
		AutomapManager.MARK_STAIRS:
			# A flight of steps: evenly spaced treads.
			for i in 4:
				var y := center.y + u * lerpf(-0.3, 0.3, i / 3.0)
				draw_line(Vector2(center.x - u * 0.3, y), Vector2(center.x + u * 0.3, y), INK, line_px)
		AutomapManager.MARK_CHEST:
			var box := Rect2(center - Vector2(u * 0.26, u * 0.19), Vector2(u * 0.52, u * 0.38))
			draw_rect(box, CHEST_FILL)
			draw_rect(box, INK, false, line_px)
			var lid_y := box.position.y + box.size.y * 0.38
			draw_line(Vector2(box.position.x, lid_y), Vector2(box.end.x, lid_y), INK, line_px)
		AutomapManager.MARK_SPIKES:
			# A row of three spikes on a base line.
			var base_y := center.y + u * 0.22
			draw_line(Vector2(center.x - u * 0.36, base_y), Vector2(center.x + u * 0.36, base_y), INK, line_px)
			for i in 3:
				var x := center.x + u * (i - 1) * 0.24
				draw_colored_polygon(PackedVector2Array([
					Vector2(x - u * 0.1, base_y), Vector2(x, base_y - u * 0.46), Vector2(x + u * 0.1, base_y)]), INK)
		AutomapManager.MARK_PUSH_BLOCK:
			# A stone block: a square with its diagonals.
			var block := Rect2(center - Vector2.ONE * u * 0.32, Vector2.ONE * u * 0.64)
			draw_rect(block, STONE_FILL)
			draw_rect(block, INK, false, line_px)
			draw_line(block.position, block.end, INK, line_px * 0.75, true)
			draw_line(Vector2(block.end.x, block.position.y), Vector2(block.position.x, block.end.y), INK, line_px * 0.75, true)
		AutomapManager.MARK_PLATE:
			# A plate set in the floor: two nested squares.
			draw_rect(Rect2(center - Vector2.ONE * u * 0.3, Vector2.ONE * u * 0.6), INK, false, line_px)
			draw_rect(Rect2(center - Vector2.ONE * u * 0.16, Vector2.ONE * u * 0.32), INK, false, line_px)
		AutomapManager.MARK_PLATFORM:
			# A slab with a double-headed arrow: it travels.
			var slab := Rect2(center - Vector2.ONE * u * 0.34, Vector2.ONE * u * 0.68)
			draw_rect(slab, STONE_FILL)
			draw_rect(slab, INK, false, line_px)
			var tip := u * 0.22
			var barb := u * 0.1
			draw_line(center - Vector2(tip, 0), center + Vector2(tip, 0), INK, line_px)
			for dir: float in [-1.0, 1.0]:
				var head := center + Vector2(tip * dir, 0)
				draw_line(head, head + Vector2(-barb * dir, -barb), INK, line_px, true)
				draw_line(head, head + Vector2(-barb * dir, barb), INK, line_px, true)
		AutomapManager.MARK_LEVER:
			# A handle standing out from the wall it is mounted on.
			var out := _away_from_wall(center, cell_center, cell_px)
			var knob := center + out * u * 0.28
			draw_line(center - out * u * 0.04, knob, INK, line_px * 1.4)
			draw_circle(knob, u * 0.1, INK)
		AutomapManager.MARK_LOCK:
			# A keyhole on the wall.
			var plate_at := center + _away_from_wall(center, cell_center, cell_px) * u * 0.1
			draw_circle(plate_at, u * 0.17, DOOR_FILL)
			draw_arc(plate_at, u * 0.17, 0.0, TAU, 20, INK, line_px, true)
			draw_circle(plate_at - Vector2(0, u * 0.04), u * 0.055, INK)
			draw_line(plate_at, plate_at + Vector2(0, u * 0.11), INK, line_px)
		AutomapManager.MARK_DRAGON:
			_draw_dragon_head(center, u, _fire_direction(node), line_px)

# Unit vector from a wall-mounted mark toward the middle of its cell (away from
# its wall), or straight down the map if it sits dead centre.
func _away_from_wall(center: Vector2, cell_center: Vector2, cell_px: float) -> Vector2:
	var offset := cell_center - center
	return offset.normalized() if offset.length() > cell_px * 0.05 else Vector2.DOWN

# Which way a fireball trap spits, on the map (falls back to the node's facing).
func _fire_direction(trap: Node3D) -> Vector2:
	var dir = trap.get("direction_vector")
	if dir is Vector3 and Vector2(dir.x, dir.z).length() > 0.01:
		return Vector2(dir.x, dir.z).normalized()
	var forward := -trap.global_transform.basis.z
	return Vector2(forward.x, forward.z).normalized()

# The trap's carved dragon head, seen from above, snout pointing where it fires.
func _draw_dragon_head(center: Vector2, u: float, forward: Vector2, line_px: float) -> void:
	var right := Vector2(-forward.y, forward.x)
	var shape: Array[Vector2] = [   # (forward, right) in cells, clockwise from the snout
		Vector2(0.44, 0.0), Vector2(0.3, 0.13), Vector2(0.08, 0.17), Vector2(-0.06, 0.3),
		Vector2(-0.44, 0.36), Vector2(-0.24, 0.14), Vector2(-0.3, 0.0),
		Vector2(-0.24, -0.14), Vector2(-0.44, -0.36), Vector2(-0.06, -0.3),
		Vector2(0.08, -0.17), Vector2(0.3, -0.13)]
	var points := PackedVector2Array()
	for p in shape:
		points.append(center + (forward * p.x + right * p.y) * u)
	draw_colored_polygon(points, DRAGON_FILL)
	points.append(points[0])
	draw_polyline(points, INK, line_px, true)
	for eye_side: float in [-1.0, 1.0]:
		draw_circle(center + (forward * 0.04 + right * 0.13 * eye_side) * u, maxf(1.0, u * 0.045), FIRE_CORE)

# The trap's fireball in flight: a flickering ball with a fading tail, drawn only
# while it is over explored floor.
func _draw_fireball(trap: Node3D, origin: Vector2, cell_px: float, cells: Dictionary) -> void:
	var ball = trap.get("fireball_entity")
	if not (ball is Node3D) or not is_instance_valid(ball) or not ball.is_inside_tree():
		return
	if not cells.has(AutomapManager.world_to_cell(ball.global_position)):
		return
	var center := origin + _map_pos(ball.global_position) * cell_px
	var heading := _fire_direction(trap)
	var time := Time.get_ticks_msec() / 1000.0
	var flicker := 1.0 + 0.18 * sin(time * 23.0) + 0.08 * sin(time * 41.0)
	var radius := maxf(3.0, cell_px * 0.26) * flicker
	for i in range(3, 0, -1):
		var fade := 1.0 - i / 4.0
		draw_circle(center - heading * radius * 0.9 * i, radius * fade, Color(FIRE_OUTER, 0.5 * fade))
	draw_circle(center, radius, FIRE_OUTER)
	draw_circle(center, radius * 0.55, FIRE_CORE)

# An arrowhead pointing the way the party faces (forward is -Z; north is up).
func _draw_party(center: Vector2, yaw: float, cell_px: float) -> void:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-forward.y, forward.x)
	var s := maxf(cell_px, 12.0)
	var points := PackedVector2Array([
		center + forward * s * 0.46,
		center - forward * s * 0.36 + right * s * 0.34,
		center - forward * s * 0.16,
		center - forward * s * 0.36 - right * s * 0.34])
	draw_colored_polygon(points, PARTY)
	points.append(points[0])
	draw_polyline(points, INK, maxf(1.0, s * 0.08), true)
