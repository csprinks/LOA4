shader_type canvas_item;

// Procedural aged parchment for the automap sheet: pale mottled paper with faint
// laid fibres, rosy water marks and darkened, uneven edges. Everything is derived
// from UV, so the sheet looks the same as the panel grows from minimap to full
// map; only the fine grain is in screen pixels.

uniform vec2 rect_size = vec2(200.0, 200.0);   // set from script; keeps noise square
uniform vec3 paper_light : source_color = vec3(0.89, 0.84, 0.70);
uniform vec3 paper_mid : source_color = vec3(0.80, 0.73, 0.57);
uniform vec3 paper_dark : source_color = vec3(0.52, 0.39, 0.30);
uniform vec3 stain_tint : source_color = vec3(0.71, 0.47, 0.42);   // rosy water marks
uniform float mottle_scale = 3.0;
uniform float fibre_strength : hint_range(0.0, 1.0) = 0.12;
uniform float stain_strength : hint_range(0.0, 1.0) = 0.65;
uniform float edge_burn : hint_range(0.0, 1.0) = 0.6;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.04;
uniform float seed = 7.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += amp * value_noise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	// Square noise space: 1 unit = the sheet's short side.
	vec2 p = UV * rect_size / min(rect_size.x, rect_size.y) + seed;

	// Broad mottling: light paper drifting into mid-tone patches, with a finer
	// cloudy layer on top so it doesn't read as a smooth gradient.
	float mottle = fbm(p * mottle_scale) * 0.65 + fbm(p * mottle_scale * 4.0 + 11.0) * 0.35;
	vec3 col = mix(paper_mid, paper_light, smoothstep(0.32, 0.62, mottle));

	// Laid fibres: thin horizontal streaks, broken up along their length.
	float fibre = value_noise(vec2(p.x * 3.0, p.y * 260.0)) * 0.6 + value_noise(vec2(p.x * 9.0, p.y * 520.0)) * 0.4;
	float fibre_mask = smoothstep(0.25, 0.7, fbm(p * 4.0 + 31.0));
	col *= 1.0 - fibre_strength * (fibre - 0.5) * fibre_mask;

	// Stains: soft-edged darker blotches, each with a slightly darker tide line.
	float blot = fbm(p * 1.9 + 63.0);
	float stain = smoothstep(0.50, 0.68, blot);
	float tide = smoothstep(0.48, 0.51, blot) * (1.0 - smoothstep(0.51, 0.56, blot));
	col = mix(col, stain_tint, (stain * 0.45 + tide * 0.2) * stain_strength);

	// Foxing: sparse small brown specks.
	float speck = smoothstep(0.84, 0.94, value_noise(p * 150.0 + 3.0)) * smoothstep(0.45, 0.65, fbm(p * 3.0 + 80.0));
	col = mix(col, stain_tint * 0.8, speck * 0.2);

	// Darkened edges: distance to the nearest side, wobbled by noise so the
	// browning creeps in unevenly, plus a gentle overall vignette.
	vec2 side = min(UV, 1.0 - UV);
	float inset = min(side.x, side.y) + (fbm(p * 3.2 + 5.0) - 0.5) * 0.16;
	float burn = 1.0 - smoothstep(0.0, 0.2, inset);
	burn = max(burn, smoothstep(0.35, 0.95, length(UV - 0.5) * 1.3) * 0.5);
	col = mix(col, paper_dark, burn * edge_burn);

	// Fine grain in screen pixels.
	col += (hash(FRAGCOORD.xy + seed) - 0.5) * grain_strength;

	COLOR = vec4(col, 1.0);
}
