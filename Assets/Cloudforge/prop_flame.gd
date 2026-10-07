class_name PropFlame
extends Node3D

## The fire on a torch, sconce or candle: a small additive particle flame, built
## in code so every lit prop shares one look, plus a flicker on the prop's light.
## build_props.gd places one at each flame point of a prop and hands the first
## the prop's light to flicker.

const FLICKER_SPEED := 9.0
const FLICKER_DEPTH := 0.22    # how far the light dips, as a share of its energy

## 1.0 is a flame about 0.2 tall: a large candle. Torches are a couple of times that.
@export var flame_size: float = 1.0
## The light this flame flickers (optional).
@export var light_path: NodePath

static var _spark: GradientTexture2D
static var _ramp: GradientTexture1D
static var _shrink: CurveTexture

var _light: Light3D
var _base_energy := 0.0
var _noise := FastNoiseLite.new()
var _clock := 0.0


func _ready() -> void:
	add_child(_build_particles())
	_light = get_node_or_null(light_path) as Light3D
	if _light:
		_base_energy = _light.light_energy
		_noise.seed = randi()
		_noise.frequency = 1.0
		_clock = randf() * 100.0   # so neighbouring flames don't pulse together
	else:
		set_process(false)


func _process(delta: float) -> void:
	_clock += delta * FLICKER_SPEED
	var dip := (_noise.get_noise_1d(_clock) * 0.5 + 0.5) * FLICKER_DEPTH
	_light.light_energy = _base_energy * (1.0 - dip)


func _build_particles() -> GPUParticles3D:
	_ensure_shared()
	var s := flame_size

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.03 * s
	process.direction = Vector3.UP
	process.spread = 9.0
	process.initial_velocity_min = 0.22 * s
	process.initial_velocity_max = 0.4 * s
	process.gravity = Vector3(0.0, 0.35 * s, 0.0)
	process.scale_min = 0.75
	process.scale_max = 1.1
	process.scale_curve = _shrink
	process.color_ramp = _ramp

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _spark

	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15) * s
	quad.material = material

	var particles := GPUParticles3D.new()
	particles.name = "Fire"
	particles.amount = 10
	particles.lifetime = 0.55
	particles.preprocess = 0.55
	particles.local_coords = true
	particles.process_material = process
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


# Textures every flame shares.
static func _ensure_shared() -> void:
	if _spark != null:
		return
	var glow := Gradient.new()
	glow.set_color(0, Color(1, 1, 1, 1))
	glow.set_color(1, Color(1, 1, 1, 0))
	_spark = GradientTexture2D.new()
	_spark.gradient = glow
	_spark.fill = GradientTexture2D.FILL_RADIAL
	_spark.fill_from = Vector2(0.5, 0.5)
	_spark.fill_to = Vector2(0.5, 0.0)
	_spark.width = 64
	_spark.height = 64

	# Life of a spark: pale yellow at the wick, orange, then a dim red wisp.
	var life := Gradient.new()
	life.set_color(0, Color(1.0, 0.92, 0.6, 0.0))
	life.set_color(1, Color(0.55, 0.1, 0.02, 0.0))
	life.add_point(0.12, Color(1.0, 0.8, 0.4, 0.5))
	life.add_point(0.55, Color(1.0, 0.42, 0.1, 0.32))
	_ramp = GradientTexture1D.new()
	_ramp.gradient = life

	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	_shrink = CurveTexture.new()
	_shrink.curve = curve
