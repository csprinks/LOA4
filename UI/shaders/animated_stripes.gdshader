shader_type canvas_item;

// Gradient animated stripes (adapted from godotshaders.com/shader/gradient-animated-stripes).
// Used as the fill of a StatBar; color_stripe/color_gap are set per-instance
// (red for HP, green for AP).

uniform vec4 color_gap : source_color = vec4(0.25, 0.25, 0.25, 0.0);
uniform vec4 color_stripe : source_color = vec4(1.0, 0.75, 0.0, 1.0);

uniform sampler2D stripe_gradient;

uniform float divisions = 8.0;
uniform float speed = 0.1;
uniform float angle = 0.7854;

uniform float stripe_width : hint_range(0.01, 1.0) = 0.5;

void fragment() {
	float w = cos(angle) * UV.x + sin(angle) * UV.y;
	w -= TIME * speed;

	float pattern = fract(w * divisions);

	float stripe_uv = pattern / stripe_width;

	float inside_stripe = step(pattern, stripe_width);

	float gradient_alpha = texture(
		stripe_gradient,
		vec2(clamp(stripe_uv, 0.0, 1.0), 0.5)
	).r;

	float stripe_mask = inside_stripe * gradient_alpha;

	COLOR = mix(
		color_gap,
		color_stripe,
		stripe_mask
	);

	COLOR.a = mix(
		color_gap.a,
		color_stripe.a,
		stripe_mask
	);
}
