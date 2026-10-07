@tool
class_name LevelAtmosphere
extends RefCounted

## The look every built level's Environment shares: dim ambient light so torches
## and sconces do the lighting, contact shadows in the corners, filmic tonemapping,
## glow off the flames and a little fog for depth. Applied when a level is built
## and again when it loads (player_loading.gd), so levels built before a change
## here pick it up without a rebuild.

## Ambient light of a level with no sky: just enough to find the walls by.
const INDOOR_AMBIENT_COLOR := Color(0.45, 0.48, 0.6)
const INDOOR_AMBIENT_ENERGY := 0.38
## How much of the sky's own light fills a level that has one. Ambient light is not
## stopped by ceilings, so at full strength roofed rooms come out as flat as the
## open ground; the sun still lights whatever it reaches.
const SKY_AMBIENT_ENERGY := 0.45
const INDOOR_FOG_COLOR := Color(0.05, 0.045, 0.05)
const INDOOR_FOG_DENSITY := 0.018
const SKY_FOG_DENSITY := 0.004

## Dress `env`. `has_sky` = the level has a painted sky (LevelSky), which owns the
## background and the colour of the ambient light; without one the level is a
## dark interior.
static func apply(env: Environment, has_sky: bool) -> void:
	if env == null:
		return
	if has_sky:
		env.ambient_light_energy = SKY_AMBIENT_ENERGY
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = INDOOR_AMBIENT_COLOR
		env.ambient_light_energy = INDOOR_AMBIENT_ENERGY

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 4.0

	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.5
	env.ssao_power = 1.6
	# Let it darken torchlit corners too, not just the ambient fill.
	env.ssao_light_affect = 0.35

	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Puddles and polished floors mirror the flames and the lit walls behind them.
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3

	env.fog_enabled = true
	env.fog_sun_scatter = 0.0
	if has_sky:
		# Outdoors the haze takes the sky's colour and leaves the sky itself alone.
		env.fog_density = SKY_FOG_DENSITY
		env.fog_aerial_perspective = 1.0
		env.fog_sky_affect = 0.0
	else:
		env.fog_density = INDOOR_FOG_DENSITY
		env.fog_light_color = INDOOR_FOG_COLOR
		env.fog_aerial_perspective = 0.0
		env.fog_sky_affect = 1.0

## Dress the environment of a built level (`root` = its root node).
static func apply_to_level(root: Node) -> void:
	var world := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		apply(world.environment, world.environment.background_mode == Environment.BG_SKY)
