@tool
class_name LevelSky
extends RefCounted

## The volumetric cloud sky a floor can have (shader and settings brought over
## from Cloudforge). A floor stores its settings in GridLevelData.sky; an empty
## dictionary, or "enabled": false, means no sky: the plain dark backdrop of an
## underground level. The Level Editor's Sky panel edits the settings, the build
## hands them to the level's WorldEnvironment (level_sky_env.gd), and apply()
## turns them into a Sky, ambient light and - optionally - the sun's angle.

const SHADER_PATH := "res://addons/level_painter/sky/volumetric_sky.gdshader"

## Settings that are not shader uniforms of the same name.
const NOT_UNIFORMS := ["enabled", "wind_angle", "sun_yaw", "sun_pitch", "sun_energy", "link_sun"]

## Every setting and its starting value. Angles are degrees.
static func defaults() -> Dictionary:
	return {
		"enabled": false,

		"sky_top_color": Color(0.24, 0.47, 0.86),
		"sky_horizon_color": Color(0.78, 0.87, 0.96),
		"sky_ground_color": Color(0.42, 0.45, 0.50),
		"sky_energy": 1.0,
		"sky_gradient_power": 0.55,

		"cloud_coverage": 0.55,
		"cloud_softness": 0.16,
		"cloud_scale": 1.0,
		"cloud_detail": 0.35,
		"cloud_contrast": 1.35,
		"cloud_height": 0.22,
		"cloud_brightness": 1.15,

		"cloud_bright_color": Color(1.0, 1.0, 1.0),
		"cloud_mid_color": Color(0.94, 0.95, 0.97),
		"cloud_dark_color": Color(0.70, 0.75, 0.84),
		"atmosphere_blend": 0.18,
		"horizon_blend": 0.25,

		"cloud_speed": 0.01,
		"wind_angle": 180.0,          # 180 = the shader's default drift (0, -1)
		"cloud_evolution_speed": 0.01,

		"sun_color": Color(1.0, 0.96, 0.88),
		"sun_size": 0.004,
		"sun_intensity": 14.0,
		"sun_yaw": 0.0,
		"sun_pitch": 45.0,
		"sun_energy": 0.35,
		"link_sun": true,             # aim the level's sunlight at the sun in the sky
	}

## Named looks: partial overrides laid over the current settings.
const PRESETS := {
	"Clear Day": {
		"sky_top_color": Color(0.24, 0.47, 0.86), "sky_horizon_color": Color(0.78, 0.87, 0.96),
		"cloud_coverage": 0.38, "cloud_brightness": 1.15, "cloud_speed": 0.01,
		"sun_intensity": 14.0, "sun_color": Color(1.0, 0.96, 0.88), "sun_pitch": 55.0,
		"sky_energy": 1.0, "cloud_dark_color": Color(0.70, 0.75, 0.84), "sun_energy": 0.45,
	},
	"Overcast": {
		"sky_top_color": Color(0.55, 0.59, 0.65), "sky_horizon_color": Color(0.72, 0.74, 0.78),
		"cloud_coverage": 0.86, "cloud_brightness": 0.95, "cloud_speed": 0.02,
		"sun_intensity": 2.0, "sun_color": Color(0.85, 0.87, 0.9), "sun_pitch": 40.0,
		"sky_energy": 0.9, "cloud_dark_color": Color(0.55, 0.58, 0.64), "sun_energy": 0.28,
	},
	"Sunset": {
		"sky_top_color": Color(0.22, 0.28, 0.55), "sky_horizon_color": Color(0.98, 0.55, 0.28),
		"cloud_coverage": 0.55, "cloud_brightness": 1.0, "cloud_speed": 0.008,
		"sun_intensity": 18.0, "sun_color": Color(1.0, 0.62, 0.32), "sun_pitch": 6.0,
		"sky_energy": 1.0, "cloud_dark_color": Color(0.36, 0.28, 0.38), "sun_energy": 0.32,
	},
	"Storm": {
		"sky_top_color": Color(0.16, 0.18, 0.24), "sky_horizon_color": Color(0.42, 0.44, 0.5),
		"cloud_coverage": 0.92, "cloud_brightness": 0.7, "cloud_speed": 0.06,
		"sun_intensity": 1.0, "sun_color": Color(0.7, 0.75, 0.85), "sun_pitch": 30.0,
		"sky_energy": 0.7, "cloud_dark_color": Color(0.16, 0.18, 0.24), "sun_energy": 0.2,
	},
	"Night": {
		"sky_top_color": Color(0.02, 0.03, 0.09), "sky_horizon_color": Color(0.08, 0.11, 0.22),
		"cloud_coverage": 0.45, "cloud_brightness": 0.35, "cloud_speed": 0.012,
		"sun_intensity": 6.0, "sun_color": Color(0.72, 0.8, 1.0), "sun_pitch": 35.0,
		"sky_energy": 0.6, "cloud_dark_color": Color(0.06, 0.08, 0.16), "sun_energy": 0.12,
	},
}

## The Sky panel's rows. "section" = heading, type "color" = a colour button,
## otherwise a slider with min / max / step (and an optional readout format).
const ROWS := [
	{"section": "Sky"},
	{"key": "sky_top_color", "label": "Zenith", "type": "color"},
	{"key": "sky_horizon_color", "label": "Horizon", "type": "color"},
	{"key": "sky_ground_color", "label": "Below", "type": "color"},
	{"key": "sky_energy", "label": "Brightness", "min": 0.1, "max": 3.0, "step": 0.01},
	{"key": "sky_gradient_power", "label": "Gradient", "min": 0.2, "max": 5.0, "step": 0.01},

	{"section": "Clouds"},
	{"key": "cloud_coverage", "label": "Coverage", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "cloud_softness", "label": "Softness", "min": 0.01, "max": 1.0, "step": 0.01},
	{"key": "cloud_scale", "label": "Size", "min": 0.3, "max": 6.0, "step": 0.05},
	{"key": "cloud_height", "label": "Altitude", "min": 0.03, "max": 0.8, "step": 0.01},
	{"key": "cloud_detail", "label": "Detail", "min": 0.0, "max": 2.0, "step": 0.01},
	{"key": "cloud_contrast", "label": "Volume", "min": 0.5, "max": 3.0, "step": 0.01},
	{"key": "cloud_brightness", "label": "Cloud light", "min": 0.0, "max": 3.0, "step": 0.01},
	{"key": "cloud_bright_color", "label": "Highlight", "type": "color"},
	{"key": "cloud_mid_color", "label": "Body", "type": "color"},
	{"key": "cloud_dark_color", "label": "Shadow", "type": "color"},
	{"key": "atmosphere_blend", "label": "Haze", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "horizon_blend", "label": "Horizon mix", "min": 0.0, "max": 1.0, "step": 0.01},

	{"section": "Weather"},
	{"key": "cloud_speed", "label": "Wind speed", "min": 0.0, "max": 0.3, "step": 0.001, "fmt": "%.3f"},
	{"key": "wind_angle", "label": "Wind dir °", "min": 0.0, "max": 360.0, "step": 1.0, "fmt": "%.0f"},
	{"key": "cloud_evolution_speed", "label": "Churn", "min": 0.0, "max": 0.15, "step": 0.001, "fmt": "%.3f"},

	{"section": "Sun"},
	{"key": "sun_color", "label": "Colour", "type": "color"},
	{"key": "sun_pitch", "label": "Height °", "min": -10.0, "max": 89.0, "step": 1.0, "fmt": "%.0f"},
	{"key": "sun_yaw", "label": "Compass °", "min": -180.0, "max": 180.0, "step": 1.0, "fmt": "%.0f"},
	{"key": "sun_size", "label": "Disc size", "min": 0.0005, "max": 0.05, "step": 0.0005, "fmt": "%.4f"},
	{"key": "sun_intensity", "label": "Glare", "min": 0.0, "max": 30.0, "step": 0.1},
	{"key": "sun_energy", "label": "Sunlight", "min": 0.0, "max": 4.0, "step": 0.01},
]

static var _noise_tex: NoiseTexture2D

## Full settings for a floor: the defaults with whatever the floor stores on top.
static func settings_for(stored: Dictionary) -> Dictionary:
	var out := defaults()
	for key in stored:
		if out.has(key):
			out[key] = stored[key]
	return out

static func is_enabled(stored: Dictionary) -> bool:
	return bool(stored.get("enabled", false))

## `settings` with a preset laid over it (and the sky switched on).
static func with_preset(settings: Dictionary, preset_name: String) -> Dictionary:
	var out := settings.duplicate()
	var preset: Dictionary = PRESETS.get(preset_name, {})
	for key in preset:
		out[key] = preset[key]
	out["enabled"] = true
	return out

## Unit vector from the level toward the sun.
static func sun_vector(settings: Dictionary) -> Vector3:
	var yaw := deg_to_rad(float(settings["sun_yaw"]))
	var pitch := deg_to_rad(float(settings["sun_pitch"]))
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()

## A fresh sky material with the shared cloud noise, ready for push().
static func make_material() -> ShaderMaterial:
	if _noise_tex == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.0045
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		noise.fractal_lacunarity = 2.1
		noise.fractal_gain = 0.5
		_noise_tex = NoiseTexture2D.new()
		_noise_tex.width = 512
		_noise_tex.height = 512
		_noise_tex.seamless = true          # the cloud UVs tile forever as you look around
		_noise_tex.generate_mipmaps = true  # kills the shimmer where the plane skews at the horizon
		_noise_tex.noise = noise
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH)
	material.set_shader_parameter("cloud_noise_texture", _noise_tex)
	return material

## Send the settings to a sky material.
static func push(material: ShaderMaterial, settings: Dictionary) -> void:
	for key in settings:
		if not (key in NOT_UNIFORMS):
			material.set_shader_parameter(key, settings[key])
	var wind := deg_to_rad(float(settings["wind_angle"]))
	material.set_shader_parameter("cloud_direction", Vector2(sin(wind), cos(wind)))
	material.set_shader_parameter("sun_direction", -sun_vector(settings))

## Give `environment` the sky described by `settings` and, if they ask for it,
## aim `sun` to match. Returns the sky material (push() to it again to restyle a
## live sky), or null when the sky is off and nothing was touched.
static func apply(environment: Environment, sun: DirectionalLight3D, settings: Dictionary) -> ShaderMaterial:
	if environment == null or not bool(settings.get("enabled", false)):
		return null
	var material := make_material()
	push(material, settings)
	var sky := Sky.new()
	sky.sky_material = material
	# Incremental, so the radiance map keeps up with moving clouds without a full
	# rebuild each frame.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 1.0
	aim_sun(sun, settings)
	return material

## Point the level's sunlight where the sky's sun is, in its colour and strength.
static func aim_sun(sun: DirectionalLight3D, settings: Dictionary) -> void:
	if sun == null or not bool(settings.get("link_sun", true)):
		return
	sun.rotation = Vector3(-deg_to_rad(float(settings["sun_pitch"])), deg_to_rad(float(settings["sun_yaw"])), 0.0)
	sun.light_color = settings["sun_color"]
	sun.light_energy = float(settings["sun_energy"])
