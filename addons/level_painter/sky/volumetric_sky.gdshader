shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.22, 0.45, 0.85);
uniform vec3 sky_horizon_color : source_color = vec3(0.78, 0.87, 0.96);
uniform vec3 sky_ground_color : source_color = vec3(0.42, 0.44, 0.48);
uniform float sky_energy : hint_range(0.1, 5.0) = 1.0;
uniform float sky_gradient_power : hint_range(0.2, 6.0) = 1.0;

uniform sampler2D cloud_noise_texture : repeat_enable, filter_linear_mipmap;
uniform float cloud_scale = 1.9;
// 0 = clear sky, 1 = solid overcast. Remapped to the noise cut-off below.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float cloud_softness : hint_range(0.01, 1.0) = 0.16;
uniform float cloud_detail : hint_range(0.0, 2.0) = 0.7;
uniform float cloud_contrast : hint_range(0.5, 3.0) = 1.35;
// How far away the cloud plane feels: small = a high dome, large = low and flat.
uniform float cloud_height : hint_range(0.03, 0.8) = 0.15;

uniform vec3 cloud_bright_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_mid_color : source_color = vec3(0.82, 0.84, 0.88);
uniform vec3 cloud_dark_color : source_color = vec3(0.50, 0.54, 0.62);
uniform float cloud_brightness : hint_range(0.0, 3.0) = 1.15;

uniform float atmosphere_blend : hint_range(0.0, 1.0) = 0.22;
uniform float horizon_blend : hint_range(0.0, 1.0) = 0.35;
uniform float atmosphere_horizon_strength : hint_range(0.0, 2.0) = 1.0;
uniform float atmosphere_zenith_strength : hint_range(0.0, 2.0) = 0.35;

uniform vec2 cloud_direction = vec2(0.0, -1.0);
uniform float cloud_speed : hint_range(0.0, 0.5) = 0.01;
uniform float cloud_evolution_speed : hint_range(0.0, 0.2) = 0.01;
uniform float edge_warp_strength : hint_range(0.0, 1.0) = 0.08;
uniform float edge_warp_scale = 3.0;

uniform float horizon_fade : hint_range(0.0, 1.0) = 0.18;
uniform float zenith_density : hint_range(0.0, 2.0) = 1.0;

// travel direction of the scene's DirectionalLight3D (-Z of its basis)
uniform vec3 sun_direction = vec3(0.4, -0.5, 0.2);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float sun_size : hint_range(0.0005, 0.05) = 0.004;
uniform float sun_intensity : hint_range(0.0, 30.0) = 14.0;

uniform float random_light_strength : hint_range(0.0, 2.0) = 0.4;
uniform float random_light_scale = 0.7;

void sky() {
	vec3 dir = normalize(EYEDIR);

	float up = clamp(dir.y, 0.0, 1.0);
	vec3 base_sky = mix(sky_horizon_color, sky_top_color, pow(up, sky_gradient_power));
	base_sky = mix(sky_ground_color, base_sky, smoothstep(-0.12, 0.02, dir.y));
	base_sky *= sky_energy;

	vec2 cloud_uv = dir.xz / max(dir.y + cloud_height, cloud_height);
	cloud_uv *= cloud_scale;
	cloud_uv += cloud_direction * TIME * cloud_speed;

	// Slow drift of the noise field itself, so clouds re-form instead of sliding
	// past as one rigid sheet.
	vec2 evolution_offset = vec2(
		sin(TIME * cloud_evolution_speed),
		cos(TIME * cloud_evolution_speed * 0.83)
	) * 0.35;
	vec2 macro_shift = vec2(sin(TIME * 0.003), cos(TIME * 0.0027)) * 0.12;

	float base_noise = texture(cloud_noise_texture, cloud_uv + macro_shift).r;
	float secondary_noise = texture(cloud_noise_texture,
		cloud_uv * 0.55 + vec2(0.23, 0.37) + evolution_offset * 0.4).r;
	float detail_noise = texture(cloud_noise_texture,
		cloud_uv * 2.4 + evolution_offset).r;

	float noise = base_noise + secondary_noise * 0.5 - detail_noise * cloud_detail;

	// turbulence strongest at mid-tones, so it chews edges rather than punching holes
	float edge_noise = texture(cloud_noise_texture,
		cloud_uv * edge_warp_scale + evolution_offset * 1.7).r;
	edge_noise = (edge_noise - 0.5) * edge_warp_strength;
	noise += edge_noise * (1.0 - abs(noise - 0.5) * 2.0);

	noise = clamp(noise, 0.0, 1.0);
	noise = pow(noise, cloud_contrast);

	// coverage is authored 0..1 (clear → overcast); the shader wants a cut-off
	float cut_off = mix(0.95, 0.05, cloud_coverage);
	float clouds = smoothstep(cut_off, cut_off + cloud_softness, noise);
	float overhead_mask = pow(max(dir.y, 0.0), 0.35);
	clouds *= mix(horizon_fade, zenith_density, overhead_mask);
	// fade out near the horizon, where the skewed plane tears mip selection into streaks
	clouds *= smoothstep(0.0, 0.05, dir.y);

	vec3 light_dir = normalize(-sun_direction);   // points at the sun
	float sun_dot = dot(dir, light_dir);

	float sun_core = smoothstep(1.0 - sun_size, 1.0 - sun_size * 0.35, sun_dot);
	float sun_glow = pow(clamp(sun_dot, 0.0, 1.0), 120.0);
	float wide_glow = pow(clamp(sun_dot, 0.0, 1.0), 18.0) * 0.18;

	float thickness = smoothstep(0.2, 0.9, noise);

	float glow_occlusion = (1.0 - clouds) * (1.0 - thickness * 0.85);
	float sun_visibility = 1.0 - clouds * 0.92;

	// damp the disc in the radiance cubemap so surfaces don't mirror the sun
	float disc_intensity = sun_intensity * (AT_CUBEMAP_PASS ? 0.35 : 1.0);
	vec3 sun_light = sun_color * sun_core * disc_intensity * sun_visibility;
	vec3 glow_light = sun_color * (sun_glow * 1.4 + wide_glow) * glow_occlusion;

	// 1 = high sun, 0 = sunset: swaps the lit face of the clouds top ↔ bottom
	float day_factor = clamp(light_dir.y * 3.0, 0.0, 1.0);
	float top_light = max(dir.y, 0.0);
	float bottom_light = pow(1.0 - max(dir.y, 0.0), 1.5);
	float vertical_light = mix(bottom_light, top_light, day_factor);
	// keep a floor so clouds seen from below don't go flat grey
	vertical_light = mix(0.3, 1.0, vertical_light);

	float sun_wrap = pow(clamp(sun_dot * 0.5 + 0.5, 0.0, 1.0), 1.5);
	float edge_light = pow(1.0 - thickness, 2.2) * vertical_light * sun_wrap;
	float body_shadow = thickness * mix(0.45, 0.75, day_factor);

	float random_light = texture(cloud_noise_texture,
		cloud_uv * random_light_scale + evolution_offset * 0.2).r;
	random_light = smoothstep(0.6, 0.92, random_light);

	float lighting = edge_light * 1.3
		+ random_light * random_light_strength
		- body_shadow
		- thickness * 0.15;
	lighting = clamp(lighting, 0.0, 1.0);

	vec3 cloud_color = mix(cloud_dark_color, cloud_mid_color, lighting);
	cloud_color = mix(cloud_color, cloud_bright_color, edge_light);

	float atmosphere_factor = mix(atmosphere_horizon_strength,
		atmosphere_zenith_strength, max(dir.y, 0.0)) * atmosphere_blend;
	cloud_color = mix(cloud_color, base_sky, atmosphere_factor);
	cloud_color *= cloud_brightness;

	float horizon_amount = pow(1.0 - max(dir.y, 0.0), 2.5);
	cloud_color = mix(cloud_color, base_sky, horizon_amount * horizon_blend);

	vec3 sky_with_sun = base_sky + glow_light + sun_light;
	COLOR = mix(sky_with_sun, cloud_color, clouds);
}
