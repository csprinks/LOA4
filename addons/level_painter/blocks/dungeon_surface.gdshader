shader_type spatial;

// The material every painted wall, floor and ceiling wears (see WallTextures).
// World-space triplanar, so neighbouring panels and corner posts line up without
// any UV work, plus three things a StandardMaterial3D can't do:
//   - slow world-space noise shifts brightness, hue and roughness, so no two
//     stretches of the same texture look alike;
//   - grime by height: walls are darker and damp near the floor and sooty near
//     the ceiling, floors gather dirt in patches, ceilings are smoke-stained;
//   - parallax depth from a Displacement map (which the built-in material
//     refuses to combine with triplanar);
//   - wear: streaks, moss, cracks and rippling puddles, and a slow pulse on
//     sets that have an Emission map.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metalness_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ao_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_ao_map = false;
uniform bool has_height_map = false;
// Polished tile, sheet metal and the like: no relief worth a parallax shift or
// any occlusion, whatever pattern its colour map carries.
uniform bool smooth_surface = false;

// Repeats per world unit along x / y / z (WallTextures works it out from the image's shape).
uniform vec3 uv_scale = vec3(0.5);
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
// How hard occlusion (the AO map, or the cavities guessed from the colour map) bites.
uniform float ao_strength : hint_range(0.0, 1.0) = 0.8;
// How far, in world units, the darkest part of the height map sits behind the surface.
uniform float parallax_depth : hint_range(0.0, 0.2) = 0.05;
// Strength of the patchy brightness / hue / roughness drift.
uniform float variation : hint_range(0.0, 1.0) = 0.22;
// Strength of the damp, dirt and soot.
uniform float grime : hint_range(0.0, 1.0) = 0.55;
// Strength of the streaks, moss, cracks and puddles.
uniform float wear : hint_range(0.0, 1.0) = 0.6;
// The level's painted wear, one texel per grid cell: 0 clean, 0.5 normal, 1 heavy.
uniform sampler2D wear_map : filter_linear, repeat_disable;
uniform bool has_wear_map = false;
uniform vec2 wear_grid = vec2(1.0);   // cells across and down
uniform float cell_size = 2.0;
// Floor is at world y = 0; ceilings sit this high.
uniform float wall_height = 3.0;
uniform sampler2D emission_map : source_color, hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_emission_map = false;
uniform float emission_energy = 2.0;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Tangent frame for triplanar normal mapping (the same one StandardMaterial3D uses).
	vec3 n = abs(world_normal);
	TANGENT = vec3(0.0, 0.0, -1.0) * n.x + vec3(1.0, 0.0, 0.0) * n.y + vec3(1.0, 0.0, 0.0) * n.z;
	TANGENT = inverse(MODEL_NORMAL_MATRIX) * normalize(TANGENT);
	BINORMAL = vec3(0.0, 1.0, 0.0) * n.x + vec3(0.0, 0.0, -1.0) * n.y + vec3(0.0, 1.0, 0.0) * n.z;
	BINORMAL = inverse(MODEL_NORMAL_MATRIX) * normalize(BINORMAL);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float cloudy(vec3 p) {
	return value_noise(p) * 0.55 + value_noise(p * 2.3 + 17.0) * 0.3 + value_noise(p * 5.1 + 43.0) * 0.15;
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

// The net of borders between scattered cells, which cracks run along.
// xy: unit direction across the nearest border; z: distance to it.
vec3 crack_field(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 nearest = vec2(8.0);
	vec2 second = vec2(8.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + hash2(cell + o) - f;
			if (dot(r, r) < dot(nearest, nearest)) {
				second = nearest;
				nearest = r;
			} else if (dot(r, r) < dot(second, second)) {
				second = r;
			}
		}
	}
	vec2 across = normalize(second - nearest);
	return vec3(across, dot(0.5 * (nearest + second), across));
}

// One sample per projection plane, weighted by how squarely the face looks down that axis.
vec4 triplanar(sampler2D map, vec2 uv_x, vec2 uv_y, vec2 uv_z, vec3 weights) {
	return texture(map, uv_x) * weights.x + texture(map, uv_y) * weights.y + texture(map, uv_z) * weights.z;
}

void fragment() {
	vec3 weights = abs(normalize(world_normal));
	weights /= weights.x + weights.y + weights.z;

	const vec3 FLIP = vec3(1.0, -1.0, 1.0);
	vec3 p = world_pos * uv_scale * FLIP;
	vec2 uv_x = p.zy * vec2(-1.0, 1.0);
	vec2 uv_y = p.xz;
	vec2 uv_z = p.xy;

	if (has_height_map) {
		// A point sunk below the face is seen further along the eye ray: slide each
		// plane's lookup that way, by more the deeper it is and the shallower the view.
		vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 slide = -view * uv_scale * FLIP * parallax_depth;
		uv_x += slide.zy * vec2(-1.0, 1.0) * (1.0 - texture(height_map, uv_x).r) / max(abs(view.x), 0.35);
		uv_y += slide.xz * (1.0 - texture(height_map, uv_y).r) / max(abs(view.y), 0.35);
		uv_z += slide.xy * (1.0 - texture(height_map, uv_z).r) / max(abs(view.z), 0.35);
	}

	vec3 albedo = triplanar(albedo_map, uv_x, uv_y, uv_z, weights).rgb;
	float roughness = triplanar(roughness_map, uv_x, uv_y, uv_z, weights).r;

	float occlusion;
	if (has_ao_map) {
		occlusion = triplanar(ao_map, uv_x, uv_y, uv_z, weights).r;
	} else if (smooth_surface) {
		occlusion = 1.0;
	} else {
		// No AO map: whatever is darker than its blurred surroundings is a crevice.
		vec3 blurred = textureLod(albedo_map, uv_x, 5.0).rgb * weights.x
				+ textureLod(albedo_map, uv_y, 5.0).rgb * weights.y
				+ textureLod(albedo_map, uv_z, 5.0).rgb * weights.z;
		occlusion = smoothstep(0.3, 1.0, dot(albedo, LUMA) / max(dot(blurred, LUMA), 0.001));
	}

	// Patchy drift. Sampled in 3D so it runs unbroken round corners.
	float broad = cloudy(world_pos * 0.31);
	float fine = cloudy(world_pos * 1.37 + 7.0);
	albedo *= 1.0 + (broad - 0.5) * 1.6 * variation;
	albedo *= mix(vec3(1.0), mix(vec3(0.9, 1.0, 1.1), vec3(1.1, 1.0, 0.88), fine), variation);
	roughness += (fine - 0.5) * variation;

	// Grime. Walls: a ragged damp tide mark rising from the floor, soot under the ceiling.
	float upright = 1.0 - abs(world_normal.y);
	float height = world_pos.y / wall_height;
	float damp = (1.0 - smoothstep(0.0, 0.4, height + (fine - 0.5) * 0.35)) * upright;
	float soot = smoothstep(0.7, 1.05, height + (broad - 0.5) * 0.4) * upright;
	// Floors: trodden-in dirt in patches. Ceilings: smoke stains.
	float dirt = smoothstep(0.5, 0.75, broad) * max(world_normal.y, 0.0);
	soot = max(soot, (0.35 + 0.65 * fine) * max(-world_normal.y, 0.0));

	// How worn this spot is: 0 clean, 1 normal, 2 heavy (the painter's Wear layer,
	// blended between cells), or normal everywhere on a level with none painted.
	float wear_level = 1.0;
	if (has_wear_map) {
		wear_level = textureLod(wear_map, (world_pos.xz / cell_size + 0.5) / wear_grid, 0.0).r * 2.0;
	}
	float worn = min(wear * wear_level, 1.0);
	// Heavy wear also spreads: marks turn up in places normal wear leaves alone.
	float spread = (wear_level - 1.0) * 0.15;
	float soil = grime * min(wear_level, 1.4);

	albedo *= 1.0 - 0.45 * soil * max(damp, dirt);
	albedo *= 1.0 - 0.5 * soil * soot;
	roughness = mix(roughness, roughness * 0.55, min(damp * soil, 1.0));
	roughness = mix(roughness, 1.0, min(max(soot, dirt) * soil, 1.0));

	// Wear: marks that would otherwise be decals, grown from world-space noise so
	// a level always carries them in the same places.
	// Streaks: dark runs bleeding down a wall from under the cornice.
	float along = world_pos.z * weights.x + world_pos.x * weights.z;
	float streak = smoothstep(0.6, 0.9, value_noise(vec3(along * 3.1, world_pos.y * 0.35, 5.0)))
			* smoothstep(0.15, 0.9, height) * upright * (0.5 + 0.5 * fine) * worn;
	// Moss: wherever it is damp or dirty, thickest in the joints.
	float mossy = max(max(damp, dirt * 0.5), upright * (1.0 - smoothstep(0.1, 0.55, height)));
	float moss = smoothstep(0.42, 0.62, value_noise(world_pos * 0.9 + 23.0) * 0.7 + value_noise(world_pos * 6.3) * 0.3 + spread)
			* mossy * mix(0.35, 1.0, 1.0 - occlusion) * min(worn * 1.5, 1.0);
	// Cracks: hairline fractures. The path is jittered at three scales so it runs
	// jagged, and a crack ends by narrowing to nothing rather than by fading.
	vec2 face = world_pos.zy * weights.x + world_pos.xz * weights.y + world_pos.xy * weights.z;
	vec2 jitter = vec2(value_noise(world_pos * 2.7 + 11.0), value_noise(world_pos * 2.7 + 57.0)) * 0.3
			+ vec2(value_noise(world_pos * 9.0 + 5.0), value_noise(world_pos * 9.0 + 71.0)) * 0.08
			+ vec2(value_noise(world_pos * 31.0), value_noise(world_pos * 31.0 + 19.0)) * 0.02;
	vec3 field = crack_field(face * 0.7 + jitter);
	float crack_width = mix(0.0015, 0.007, value_noise(world_pos * 3.3 + 40.0))
			* smoothstep(0.45, 0.62, value_noise(world_pos * 0.23 + 91.0) + spread)
			* smoothstep(0.42, 0.6, value_noise(world_pos * 1.1 + 3.0) + spread)
			* min(worn * 1.6, 1.0);
	float pixel = fwidth(field.z);
	// Narrower than a pixel, it thins out instead of staying a pixel wide.
	float crack = (1.0 - smoothstep(crack_width - pixel, crack_width + pixel, field.z))
			* min(crack_width / max(pixel, 0.00001), 1.0);
	// The lip either side: the surface breaks down into the crack, baring paler stone.
	float lip = (1.0 - smoothstep(crack_width, crack_width * 4.0 + 0.001, field.z)) * step(0.0002, crack_width);	// Puddles: standing water on the floor, pooling in the low parts of the surface.
	float pool = value_noise(vec3(world_pos.xz * 0.55, 77.0)) * 0.8 + fine * 0.2 - 0.62 - (1.0 - worn) * 0.25 + spread * 0.33;
	if (has_height_map) {
		pool -= (texture(height_map, uv_y).r - 0.5) * 0.12;
	}
	float puddle = smoothstep(0.0, 0.03, pool) * step(0.9, world_normal.y) * step(abs(world_pos.y), 0.05);

	albedo *= 1.0 - 0.4 * streak;
	albedo = mix(albedo, vec3(0.1, 0.16, 0.05) * (0.6 + 2.0 * dot(albedo, LUMA)), moss * 0.85);
	albedo *= 1.0 + 0.12 * lip * (1.0 - crack);
	albedo *= (1.0 - 0.93 * crack) * (1.0 - 0.45 * puddle);
	roughness = mix(roughness, 0.95, moss);
	roughness = mix(roughness, 1.0, crack);
	roughness = mix(roughness, 0.05, puddle);

	// Water lies flat over the surface's relief, and never quite sits still.
	vec3 normal = triplanar(normal_map, uv_x, uv_y, uv_z, weights).rgb;
	// Face axes -> the tangent frame set up in vertex(), which runs backwards on two of them.
	normal.xy += field.xy * vec2(1.0 - 2.0 * weights.x, 1.0 - 2.0 * weights.y) * lip * 0.3;
	normal = mix(normal, vec3(0.5, 0.5, 1.0), puddle);
	normal.xy += puddle * 0.012 * vec2(
			sin(TIME * 1.7 + world_pos.x * 11.0 + world_pos.z * 3.0), sin(TIME * 1.3 + world_pos.z * 13.0));

	ALBEDO = albedo * tint;
	ROUGHNESS = clamp(roughness, 0.04, 1.0);
	METALLIC = triplanar(metalness_map, uv_x, uv_y, uv_z, weights).r * (1.0 - moss);
	NORMAL_MAP = normal;
	NORMAL_MAP_DEPTH = normal_strength;
	AO = mix(1.0, occlusion, ao_strength) * (1.0 - crack) * (1.0 - 0.3 * lip);
	AO_LIGHT_AFFECT = 0.4;
	if (has_emission_map) {
		// A slow pulse that drifts across the surface rather than beating as one.
		EMISSION = triplanar(emission_map, uv_x, uv_y, uv_z, weights).rgb * emission_energy
				* (0.7 + 0.3 * sin(TIME * 1.5 + broad * 6.2832));
	}
}
