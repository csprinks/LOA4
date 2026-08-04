shader_type spatial;
// Fog-of-war overlay for the automap. Rendered only by the automap camera (its
// own render layer). The reveal mask is one texel per grid cell sampled with
// NEAREST filtering, so each revealed cell is a crisp, grid-aligned square
// (crawler style), not a soft RTS blob. Opaque dark where unexplored, fully
// transparent where revealed.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D reveal_mask : filter_nearest;
uniform float grid_size = 2.0;
uniform float mask_cells = 256.0;
uniform vec4 fog_color : source_color = vec4(0.03, 0.03, 0.05, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Map world XZ to the cell texel (nearest sampling keeps tiles hard-edged).
	vec2 uv = (world_pos.xz / grid_size + vec2(mask_cells * 0.5 + 0.5)) / mask_cells;
	float revealed = texture(reveal_mask, uv).r;
	ALBEDO = fog_color.rgb;
	ALPHA = 1.0 - step(0.5, revealed);
}
