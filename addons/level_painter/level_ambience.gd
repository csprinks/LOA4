class_name LevelAmbience
extends RefCounted

## The small moving things that make a built level feel inhabited: water dripping
## from some of its ceilings and dust drifting in the glow of its lights. Added
## when a level loads (player_loading.gd), never saved into the scene, so every
## built level has them and they can be retuned here without a rebuild.

const NODE_NAME := "Ambience"
## One roofed cell in this many drips.
const DRIP_ONE_IN := 9
## Particles further from the camera than this are not drawn.
const DRAW_DISTANCE := 16.0

static func apply_to_level(root: Node3D) -> void:
	if root.has_node(NODE_NAME):
		return
	var holder := Node3D.new()
	holder.name = NODE_NAME
	root.add_child(holder)
	_add_drips(root, holder)
	_add_dust(root, holder)


#region Drips
static func _add_drips(root: Node3D, holder: Node3D) -> void:
	var ceilings := root.get_node_or_null("Ceilings")
	if ceilings == null:
		return
	var mesh := _drop_mesh()
	for slab in ceilings.get_children():
		if not String(slab.name).begins_with("Ceiling_"):
			continue
		# Seeded by the cell, so the same ceilings drip every time the level loads.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(root.name) + String(slab.name))
		if rng.randi() % DRIP_ONE_IN != 0:
			continue
		var half := GridLevelBuilder.CELL * 0.5 - 0.3
		var drip := GPUParticles3D.new()
		drip.name = "Drip_" + String(slab.name)
		drip.amount = 1
		# One drop per `lifetime`; it is only visible for the fall, at the start.
		drip.lifetime = rng.randf_range(2.5, 6.0)
		drip.preprocess = rng.randf_range(0.0, drip.lifetime)
		drip.process_material = _drop_process(GridLevelBuilder.WALL_HEIGHT, drip.lifetime)
		drip.draw_pass_1 = mesh
		drip.visibility_aabb = AABB(Vector3(-0.2, -GridLevelBuilder.WALL_HEIGHT - 0.2, -0.2),
			Vector3(0.4, GridLevelBuilder.WALL_HEIGHT + 0.4, 0.4))
		drip.visibility_range_end = DRAW_DISTANCE
		holder.add_child(drip)
		drip.position = (slab as Node3D).position * Vector3(1, 0, 1) \
			+ Vector3(rng.randf_range(-half, half), GridLevelBuilder.WALL_HEIGHT - 0.02, rng.randf_range(-half, half))

## A drop that falls `height` under gravity, then stays hidden for the rest of its life.
static func _drop_process(height: float, lifetime: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3(0, -9.8, 0)
	process.direction = Vector3.DOWN
	process.spread = 0.0
	var fall_time := sqrt(2.0 * height / 9.8)
	var visible := Gradient.new()
	visible.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	visible.offsets = PackedFloat32Array([0.0, minf(fall_time / lifetime, 1.0)])
	visible.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = visible
	process.color_ramp = ramp
	return process

static func _drop_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.85, 0.95, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.roughness = 0.1
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.018, 0.11)
	mesh.material = material
	return mesh
#endregion


#region Dust
static func _add_dust(root: Node3D, holder: Node3D) -> void:
	var mesh := _mote_mesh()
	var process := _mote_process()
	for light: OmniLight3D in root.find_children("*", "OmniLight3D", true, false):
		if _is_carried(light, root):
			continue
		var dust := GPUParticles3D.new()
		dust.name = "Dust"
		dust.amount = 18
		dust.lifetime = 7.0
		dust.preprocess = 7.0
		dust.randomness = 1.0
		dust.process_material = process
		dust.draw_pass_1 = mesh
		dust.visibility_aabb = AABB(Vector3.ONE * -2.5, Vector3.ONE * 5.0)
		dust.visibility_range_end = DRAW_DISTANCE
		holder.add_child(dust, true)
		dust.global_position = light.global_position

## A light that rides on something moving (a fireball) gathers no dust.
static func _is_carried(light: Node, root: Node) -> bool:
	var node := light.get_parent()
	while node != null and node != root:
		if node is RigidBody3D or node is CharacterBody3D:
			return true
		node = node.get_parent()
	return false

static func _mote_process() -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.3
	process.gravity = Vector3(0, 0.02, 0)   # warm air rising off the flame
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.scale_min = 0.5
	process.scale_max = 1.5
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.15
	process.turbulence_noise_scale = 3.0
	# Fade in and out, so motes never pop.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	return process

static func _mote_mesh() -> QuadMesh:
	# A soft round speck.
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var speck := GradientTexture2D.new()
	speck.gradient = falloff
	speck.fill = GradientTexture2D.FILL_RADIAL
	speck.fill_from = Vector2(0.5, 0.5)
	speck.fill_to = Vector2(1.0, 0.5)
	speck.width = 32
	speck.height = 32
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.78, 0.5, 0.5)
	material.albedo_texture = speck
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.03)
	mesh.material = material
	return mesh
#endregion
