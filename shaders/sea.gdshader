shader_type spatial;
// Ocean surface: one big transparent plane at the current tide height. The sand
// rises above it inland, so the waterline is simply where the plane meets the
// sloping beach. `shoreline_z` is pushed in every frame by sea.gd and drives the
// shallow/deep gradient and the foam band that runs up and down the sand.
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.15, 0.55, 0.60, 1.0);
// The deep colour stays in the same teal family as the shallows. A navy this
// far from the beach read as a dark maroon band across the horizon, so the open
// water now just gets a little deeper and greener instead of turning black.
uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.46, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float shallow_alpha = 0.42;
uniform float deep_alpha = 0.82;
uniform float foam_width = 2.2;
uniform float wave_height = 0.03;
// World Z of the waterline (more negative = further out to sea).
uniform float shoreline_z = -13.0;
// The plane is much wider than the wet part so the horizon is water, but it must
// never be visible inland: on land it would be a sheet hovering just under the
// sand, which a dug hole exposes as a flat white/turquoise slab. Everything this
// far behind the waterline is simply not drawn.
uniform float dry_margin = 0.35;
// How many metres offshore the water reaches its deep colour. The seabed slopes
// gently for ~22 m, so this keeps the shallows readable instead of snapping to
// deep blue right at the waterline.
uniform float deep_distance = 26.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float swell = sin(world_pos.x * 0.22 + TIME * 0.9)
		* cos(world_pos.z * 0.17 + TIME * 0.7);
	VERTEX.y += swell * wave_height;
}

void fragment() {
	// Past the waterline there is beach, not sea. The cut is softened over the
	// dry margin so a pit dug at the waterline shows a wet edge rather than a
	// razor-straight wall of water.
	float dry = smoothstep(shoreline_z, shoreline_z + dry_margin, world_pos.z);
	if (dry >= 1.0) {
		discard;
	}

	// 0 at the waterline, 1 far out to sea (the sea is on the -Z side).
	float offshore = clamp((shoreline_z - world_pos.z) / deep_distance, 0.0, 1.0);
	float ripple = sin(world_pos.x * 1.7 + TIME * 2.0)
		* cos(world_pos.z * 1.3 - TIME * 1.6);

	// Foam hugs the moving waterline and pulses gently.
	float foam = 1.0 - smoothstep(0.0, foam_width, shoreline_z - world_pos.z);
	foam *= 0.55 + 0.45 * sin(TIME * 2.2 + world_pos.x * 1.3);
	foam = clamp(foam, 0.0, 1.0);

	vec3 color = mix(shallow_color.rgb, deep_color.rgb, offshore);
	color = mix(color, foam_color.rgb, foam);
	ALBEDO = color + ripple * 0.03;
	ALPHA = max(mix(shallow_alpha, deep_alpha, offshore), foam * 0.85) * (1.0 - dry);
	ROUGHNESS = mix(0.30, 0.55, foam);
	METALLIC = 0.0;
	SPECULAR = 0.12;
	NORMAL = normalize(NORMAL + vec3(ripple * 0.07, 0.0, ripple * 0.07));
}
