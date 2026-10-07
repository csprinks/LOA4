extends SceneTree

## Builds a ready-to-place scene for every entry in CloudforgeProps.PROPS, fitted
## to this game's scale, and refreshes the Level Editor's tile catalog so the new
## props show in its Objects palette. Re-run after editing the table:
##   Godot.exe --headless --path <project> --script res://Assets/Cloudforge/build_props.gd
##
## Each scene is: a root Node3D at the cell's floor centre, the model under it
## (scaled and re-centred), a box collider if the prop is solid, and a warm light
## if it is a light source. The fitted size of each is printed.

const CATALOG_PATH := "res://addons/level_painter/default_catalog.tres"
const LIGHT_COLOR := Color(1.0, 0.72, 0.42)
## How far a hanging prop's top is sunk into the ceiling, so its ring or hook
## reads as fixed to it rather than hovering just below.
const HANG_EMBED := 0.07

func _initialize() -> void:
	var Props = load("res://Assets/Cloudforge/cloudforge_props.gd")
	DirAccess.make_dir_recursive_absolute(Props.SCENES)
	var failed := 0
	for prop in Props.PROPS:
		if not _build(Props, prop):
			failed += 1
	var catalog = load("res://addons/level_painter/tile_catalog.gd").default_catalog()
	var err := ResourceSaver.save(catalog, CATALOG_PATH)
	print("catalog: %s, %d tiles" % [error_string(err), catalog.tiles.size()])
	print("props: %d built, %d failed" % [Props.PROPS.size() - failed, failed])
	quit(1 if failed > 0 else 0)

func _build(Props, prop: Dictionary) -> bool:
	var source = load(Props.MODELS + String(prop["file"]))
	if not (source is PackedScene):
		push_error("build_props: cannot load " + String(prop["file"]))
		return false
	var model: Node3D = source.instantiate()
	var box := _aabb(model, Transform3D.IDENTITY)
	if box.size.y <= 0.0001:
		push_error("build_props: no geometry in " + String(prop["file"]))
		return false

	# Scale: the table's size rule, then the caps that keep a prop inside one cell.
	var fit := String(prop["fit"])
	var wide := maxf(box.size.x, box.size.z)
	var s := 1.0
	match fit:
		"height": s = float(prop["size"]) * Props.SCALE / box.size.y
		"footprint": s = float(prop["size"]) * Props.SCALE / wide
		"cell": s = float(prop["size"]) * Props.SCALE / maxf(wide, box.size.y)
		"scale": s = float(prop["size"]) * Props.SCALE
		"pillar": s = Props.CEILING / box.size.y
	s = minf(s, Props.MAX_FOOTPRINT / wide)
	if fit != "pillar":
		s = minf(s, Props.MAX_HEIGHT / box.size.y)
	var fitted := box.size * s

	# Placement: centred on the cell, standing on the floor - or hung from the
	# ceiling, or with its back on the wall plane (z = 0) at mounting height.
	var centre := box.get_center()
	var lift := -box.position.y * s
	var back := -centre.z * s
	if prop.get("hang", false):
		lift = Props.CEILING + HANG_EMBED - box.end.y * s
	if prop.get("wall", false):
		back = -box.position.z * s
	model.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(-centre.x * s, lift, back)) * model.transform
	model.name = "Model"

	var root := Node3D.new()
	root.name = String(prop["id"])
	root.add_child(model)
	model.owner = root
	var base := lift + box.position.y * s   # y of the model's underside

	if prop.get("solid", false):
		var body := StaticBody3D.new()
		body.name = "Body"
		# The automap must not mistake furniture for a wall.
		body.add_to_group("automap_ignore", true)
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var cube := BoxShape3D.new()
		cube.size = fitted
		# A wall prop's back is on the wall plane (z = 0), so its body sits forward
		# of it. The body is the prop's true size: the party can walk right up to a
		# shallow piece like the bookshelf and stand in its cell.
		var forward := fitted.z * 0.5 if prop.get("wall", false) else 0.0
		shape.shape = cube
		shape.position = Vector3(0.0, base + fitted.y * 0.5, forward)
		root.add_child(body)
		body.owner = root
		body.add_child(shape)
		shape.owner = root

	# Fire, and the light it gives: one light per prop, at the middle of its flames.
	var flames := _flame_points(model, String(prop.get("flame", "")))
	if prop.has("light"):
		var light := OmniLight3D.new()
		light.name = "Light"
		light.light_color = LIGHT_COLOR
		light.light_energy = float(prop["light"][0])
		light.omni_range = float(prop["light"][1])
		light.omni_attenuation = 1.4
		# No specular: a bare point light this close to a wall or ceiling otherwise
		# paints a hard white hot spot on it, like a light bulb.
		light.light_specular = 0.0
		light.shadow_enabled = false
		var at := Vector3(0.0, base + fitted.y, fitted.z * 0.5 if prop.get("wall", false) else 0.0)
		if not flames.is_empty():
			at = Vector3.ZERO
			for point in flames:
				at += point
			at /= flames.size()
		light.position = at + Vector3(0.0, 0.12, 0.0)
		root.add_child(light)
		light.owner = root
	for i in flames.size():
		var flame := Node3D.new()
		flame.name = "Flame%d" % (i + 1)
		flame.set_script(load("res://Assets/Cloudforge/prop_flame.gd"))
		flame.set("flame_size", float(prop.get("flame_size", 1.0)))
		flame.position = flames[i]
		root.add_child(flame)
		flame.owner = root
		if i == 0 and prop.has("light"):
			flame.set("light_path", NodePath("../Light"))

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, Props.scene_path(prop))
	print("%-26s %5.2f x %5.2f x %5.2f  (scale %.4f)%s" % [prop["id"], fitted.x, fitted.y, fitted.z, s,
		"" if err == OK else "  SAVE FAILED: " + error_string(err)])
	root.free()
	return err == OK

# Where a prop's fire burns, in the prop scene's space (`model` is already fitted
# and placed). "top": one point in the middle of the model's top rim, sunk a
# little into it. "wicks": the top of every hair-thin mesh.
func _flame_points(model: Node3D, mode: String) -> Array:
	var points: Array = []
	if mode == "":
		return points
	var meshes: Array = []   # one PackedVector3Array of placed vertices per mesh
	_collect_meshes(model, Transform3D.IDENTITY, meshes)
	var whole := _aabb(model, Transform3D.IDENTITY)
	if mode == "wicks":
		var thin := maxf(whole.size.x, whole.size.z) * 0.02
		for vertices: PackedVector3Array in meshes:
			var box := AABB(vertices[0], Vector3.ZERO)
			for vertex in vertices:
				box = box.expand(vertex)
			if maxf(box.size.x, box.size.z) <= thin:
				points.append(Vector3(box.get_center().x, box.end.y, box.get_center().z))
	else:
		var rim := whole.end.y - whole.size.y * 0.12
		var sum := Vector3.ZERO
		var count := 0
		for vertices: PackedVector3Array in meshes:
			for vertex in vertices:
				if vertex.y >= rim:
					sum += vertex
					count += 1
		if count > 0:
			points.append(Vector3(sum.x / count, whole.end.y - whole.size.y * 0.05, sum.z / count))
	return points

func _collect_meshes(node: Node, xform: Transform3D, out: Array) -> void:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D and node.mesh:
		var vertices := PackedVector3Array()
		for vertex in node.mesh.get_faces():
			vertices.append(local * vertex)
		if not vertices.is_empty():
			out.append(vertices)
	for child in node.get_children():
		_collect_meshes(child, local, out)

func _aabb(node: Node, xform: Transform3D) -> AABB:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	var out := AABB()
	var have := false
	if node is MeshInstance3D and node.mesh:
		# Measured from the vertices, not the mesh's own box: a box turned by a
		# rotated node swells, which hides how thin a model really is.
		for vertex in node.mesh.get_faces():
			var point: Vector3 = local * vertex
			if have:
				out = out.expand(point)
			else:
				out = AABB(point, Vector3.ZERO)
				have = true
	for child in node.get_children():
		var c := _aabb(child, local)
		if c.size == Vector3.ZERO and c.position == Vector3.ZERO:
			continue
		out = out.merge(c) if have else c
		have = true
	return out
