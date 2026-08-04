extends Node3D
class_name Automap

## Automap rig — a child of the player, so it rides level transitions.
## Renders a top-down orthographic view of the real level into a world-sharing
## SubViewport, overlaid with a per-tile shader-fog quad (AutomapManager's mask).
## Shows an always-on minimap in a corner; "toggle_automap" (M) opens a fullscreen
## map. A facing arrow marks the player.
##
## Render isolation: fog + marker sit on AUTOMAP_LAYER, which the first-person
## camera excludes (Player_Camera cull_mask), so they only appear on the map.

const AUTOMAP_LAYER := 20            # 1..20; main camera excludes this
const CAM_HEIGHT := 40.0             # top-down camera height
const FOG_HEIGHT := 14.0             # fog plane height (above walls, below camera)
const MARKER_HEIGHT := 16.0          # player arrow height (above the fog)
const VIEW_SIZE := 26.0              # orthographic view extent (world units)

var _fog: MeshInstance3D
var _marker: MeshInstance3D
var _subviewport: SubViewport
var _cam: Camera3D
var _canvas: CanvasLayer
var _fullscreen: Control
var _icons: Array[Node3D] = []

# Feature groups a mechanic can join to appear on the map, and their icon colour.
const FEATURE_GROUPS := {
	"map_stairs": Color(0.4, 1.0, 0.55),
	"map_door": Color(1.0, 0.62, 0.2),
	"map_chest": Color(1.0, 0.85, 0.25),
}

func _ready() -> void:
	_build_fog_quad()
	_build_player_marker()
	_build_viewport_and_camera()
	_build_ui()
	# Rebuild feature icons on every level change; catch the current level now.
	AutomapManager.map_reset.connect(func(_p): call_deferred("_rebuild_icons"))
	call_deferred("_rebuild_icons")

func _process(_delta: float) -> void:
	var player := _get_player()
	if player == null:
		return
	var pos := player.global_position
	# North-up camera following the player from directly above.
	_cam.global_position = Vector3(pos.x, CAM_HEIGHT, pos.z)
	# Fog stays flat and world-aligned (the shader is world-anchored).
	_fog.global_position = Vector3(pos.x, FOG_HEIGHT, pos.z)
	_fog.global_rotation = Vector3.ZERO
	# Arrow sits above the fog and spins to the player's grid facing.
	_marker.global_position = Vector3(pos.x, MARKER_HEIGHT, pos.z)
	_marker.global_rotation = Vector3(0.0, player.global_rotation.y, 0.0)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_automap"):
		_fullscreen.visible = not _fullscreen.visible

#region Build
func _build_fog_quad() -> void:
	_fog = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	_fog.mesh = plane
	_fog.layers = 1 << (AUTOMAP_LAYER - 1)
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://Automap/automap_fog.gdshader")
	mat.set_shader_parameter("reveal_mask", AutomapManager.get_mask_texture())
	mat.set_shader_parameter("grid_size", AutomapManager.GRID_SIZE)
	mat.set_shader_parameter("mask_cells", float(AutomapManager.MASK_CELLS))
	_fog.material_override = mat
	add_child(_fog)

func _build_player_marker() -> void:
	_marker = MeshInstance3D.new()
	# A flat triangle in the XZ plane pointing -Z (the player's forward).
	var arr := ArrayMesh.new()
	var verts := PackedVector3Array([
		Vector3(0.0, 0.0, -1.1), Vector3(0.75, 0.0, 0.8), Vector3(-0.75, 0.0, 0.8)])
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = verts
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	_marker.mesh = arr
	_marker.layers = 1 << (AUTOMAP_LAYER - 1)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.9, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker.material_override = mat
	add_child(_marker)

func _build_viewport_and_camera() -> void:
	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(512, 512)
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_subviewport)
	# Share the main 3D world so the automap camera renders the real level.
	_subviewport.world_3d = get_tree().root.world_3d

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = VIEW_SIZE
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # straight down
	_cam.cull_mask = (1 << 20) - 1                      # geometry + fog + marker
	_cam.current = true
	_subviewport.add_child(_cam)

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 40
	add_child(_canvas)

	# --- Always-on minimap (top-left) ---
	var size := 220
	var margin := 16
	var frame := ColorRect.new()
	frame.color = Color(0.12, 0.1, 0.08, 0.9)
	frame.position = Vector2(margin - 4, margin - 4)
	frame.size = Vector2(size + 8, size + 8)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(frame)

	var mini := TextureRect.new()
	mini.texture = _subviewport.get_texture()
	mini.position = Vector2(margin, margin)
	mini.size = Vector2(size, size)
	mini.stretch_mode = TextureRect.STRETCH_SCALE
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(mini)

	# --- Fullscreen map (toggled with M) ---
	_fullscreen = Control.new()
	_fullscreen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fullscreen.visible = false
	_fullscreen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_fullscreen)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen.add_child(bg)

	var big := TextureRect.new()
	big.texture = _subviewport.get_texture()
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen.add_child(big)
#endregion

#region Feature icons
# Scan the current level for tagged features and drop a diamond marker at each
# one's cell, parented to the level (freed with it). Icons sit at floor level, so
# the fog hides them until that tile is revealed.
func _rebuild_icons() -> void:
	for icon in _icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_icons.clear()

	var level := _current_level()
	if level == null:
		return
	for group in FEATURE_GROUPS:
		var color: Color = FEATURE_GROUPS[group]
		for node in get_tree().get_nodes_in_group(group):
			if not (node is Node3D) or not level.is_ancestor_of(node):
				continue
			var icon := _make_icon(color)
			level.add_child(icon)
			var cell := AutomapManager.world_to_cell((node as Node3D).global_position)
			icon.global_position = AutomapManager.cell_to_world(cell) + Vector3(0.0, 0.7, 0.0)
			_icons.append(icon)

func _make_icon(color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.3, 1.3)
	m.mesh = plane
	m.rotation_degrees = Vector3(0.0, 45.0, 0.0)   # diamond silhouette from above
	m.layers = 1 << (AUTOMAP_LAYER - 1)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	return m

func _current_level() -> Node:
	var lm = get_node_or_null("/root/LevelManager")
	if lm and lm.has_method("get_current_level"):
		var l = lm.get_current_level()
		if l and is_instance_valid(l):
			return l
	var p := _get_player()
	if p and p.get_parent():
		return p.get_parent()
	return null
#endregion

func _get_player() -> Node3D:
	return AutomapManager._get_player()
