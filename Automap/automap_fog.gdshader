shader_type spatial;
// Automap fog-of-war. Rendered only by the automap camera (own render layer).
// The reveal is still PER TILE (nearest-sampled mask, crisp grid squares), but the
// UNEXPLORED fill is now animated drifting mist instead of flat black — the look of
// godotshaders.com "Animated Camera Fog Overlay" (CC0), reworked as a world-space
// spatial shader driven by procedural noise so no noise textures are needed.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D reveal_mask : filter_nearest;
uniform float grid_size = 2.0;
uniform float mask_cells = 256.0;

uniform vec4 fog_color : source_color = vec4(0.03, 0.03, 0.05, 1.0);
uniform vec3 mist_tint : source_color = vec3(0.34, 0.36, 0.44);
uniform float mist_scale = 0.12;    // world units -> noise frequency
uniform float mist_speed = 1.0;     // drift speed
uniform float mist_strength = 0.55; // how much the mist lightens the fog

varying vec3 world_pos;

// --- procedural value-noise fbm (no textures) ---
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Per-tile reveal: nearest-sampled mask -> grid-aligned squares. The mask value
	// ramps 0->1 as a cell is revealed (AutomapManager tweens it), so the raw value
	// gives a smooth per-tile fade-out of the fog rather than a hard pop.
	vec2 uv = (world_pos.xz / grid_size + vec2(mask_cells * 0.5 + 0.5)) / mask_cells;
	float revealed = texture(reveal_mask, uv).r;

	// Two drifting noise layers (world-anchored) for a rolling-mist look.
	vec2 wp = world_pos.xz * mist_scale;
	float t = TIME * mist_speed;
	float n1 = fbm(wp + vec2(t * 0.8, t * 0.3));
	float n2 = fbm(wp * 1.8 - vec2(t * 0.5, t * 0.7));
	float mist = mix(n1, n2, 0.5);

	// Unexplored stays opaque (hides the level) but its colour drifts like fog.
	ALBEDO = mix(fog_color.rgb, mist_tint, mist * mist_strength);
	ALPHA = 1.0 - revealed;
}
