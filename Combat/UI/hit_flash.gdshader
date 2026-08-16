shader_type canvas_item;

// Silhouette-preserving hit flash. In a canvas_item fragment shader COLOR already
// holds this pixel's texture colour × modulate, so we just tint it toward
// `flash_color` by `flash_amount` (0 = untouched, 1 = full flash colour). Alpha is
// left alone, so only the character shape pulses — not the whole rectangle — and at
// flash_amount 0 the sprite renders exactly as it would with no shader.
// Adapted from the common "2D shake & flash" canvas shader; the shake half is
// driven in code, because a per-node shader can't transform a whole multi-child card.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.15, 0.15, 1.0);

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, flash_color.rgb, flash_amount);
}
