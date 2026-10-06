extends Node

## Renders the palette icon for every tile in the catalog (see LevelTileIcons):
## each tile's scene is posed alone in an empty world and photographed onto a
## transparent background. Needs a real renderer, so run it windowed, not headless:
##   Godot.exe --path <project> res://addons/level_painter/icons/build_icons.tscn
## then let the editor (or --import) pick up the new PNGs.

const RENDER_SIZE := 384
const ICON_SIZE := 96
const CLOUDFORGE_ICONS := "res://Assets/Cloudforge/images/icons/"
## Tiles with nothing to photograph (they are invisible in play) borrow a glyph.
const GLYPHS := { &"encounter": "bug.png", &"puzzle": "rules.png" }
## Geometry below this is left out of the framing (the pit trap's long shaft).
const FLOOR_CLIP := -0.7

var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D

func _ready() -> void:
	_build_studio()
	var catalog: TileCatalog = load("res://addons/level_painter/tile_catalog.gd").default_catalog()
	var made := 0
	for def in catalog.tiles:
		if await _shoot(def):
			made += 1
		else:
			push_warning("build_icons: no icon for " + def.display_name)
	print("icons: %d of %d tiles" % [made, catalog.tiles.size()])
	get_tree().quit()

func _build_studio() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RENDER_SIZE, RENDER_SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.75
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	_viewport.add_child(sun)
	sun.rotation_degrees = Vector3(-50, 150, 0)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.far = 200.0
	_viewport.add_child(_camera)
	_stage = Node3D.new()
	_viewport.add_child(_stage)

func _shoot(def: TileDef) -> bool:
	var image: Image = null
	if def.kind == TileDef.Kind.OBJECT and GLYPHS.has(def.name_id):
		image = (load(CLOUDFORGE_ICONS + GLYPHS[def.name_id]) as Texture2D).get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_white_to_alpha(image)
	else:
		image = await _photograph(def)
	if image == null:
		return false
	image.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return image.save_png(LevelTileIcons.path(def)) == OK

func _photograph(def: TileDef) -> Image:
	var scene = load(def.scene_path) if def.scene_path != "" else null
	if not (scene is PackedScene):
		return null
	var model: Node3D = scene.instantiate()
	_strip_scripts(model)   # a still life: nothing should open, fire or fall
	_stage.add_child(model)
	if def.kind == TileDef.Kind.OBJECT:
		model.rotation.y = deg_to_rad(def.facing_offset)   # front toward -Z, as painted facing North
	if def.is_pit:   # shown ajar, so it reads as a trap door rather than as floor
		for hinge in [["HingeA", -0.6], ["HingeB", 0.6]]:
			var flap := model.get_node_or_null(hinge[0]) as Node3D
			if flap:
				flap.rotation.z = hinge[1]
	await get_tree().process_frame

	var box := _bounds(model)
	if box.size.length() < 0.01:
		model.free()
		return null
	# Look at the front from a little to one side and above; flat things (plates,
	# floor, the pit) are seen from higher up.
	var flat := box.size.y < 0.35 * maxf(box.size.x, box.size.z)
	var toward := Vector3(-0.55, 1.3 if flat else 0.55, -1.0)
	if def.kind != TileDef.Kind.OBJECT:
		toward = Vector3(0.55, 1.3 if flat else 0.4, 1.0)
	var centre := box.get_center()
	_camera.look_at_from_position(centre + toward.normalized() * 60.0, centre)
	var reach := 0.0
	for i in 8:
		var corner := _camera.global_transform.affine_inverse() * box.get_endpoint(i)
		reach = maxf(reach, maxf(absf(corner.x), absf(corner.y)))
	_camera.size = reach * 2.0 * 1.06

	for _frame in 4:
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	if def.kind == TileDef.Kind.FLOOR and def.y_offset < 0.0:   # a pit: the floor, sunk in shadow
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(c.r * 0.35, c.g * 0.33, c.b * 0.4, c.a))
	model.free()
	return image

# The borrowed glyphs sit on opaque white: lift them off it.
func _white_to_alpha(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var alpha := 1.0 - minf(c.r, minf(c.g, c.b))
			if alpha <= 0.004:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var white := 1.0 - alpha
				image.set_pixel(x, y, Color((c.r - white) / alpha, (c.g - white) / alpha, (c.b - white) / alpha, alpha))

func _strip_scripts(node: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		_strip_scripts(child)

# World-space bounds of the solid geometry under `root`.
func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "VisualInstance3D", true, false) + [root]:
		if not (node is MeshInstance3D or node is CSGPrimitive3D) or not node.is_visible_in_tree():
			continue
		var local: AABB = node.get_aabb()
		for i in 8:
			var point: Vector3 = node.global_transform * local.get_endpoint(i)
			point.y = maxf(point.y, FLOOR_CLIP)
			box = AABB(point, Vector3.ZERO) if first else box.expand(point)
			first = false
	return box
