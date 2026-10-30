shader_type spatial;
// Ocean surface: one big transparent plane at the current tide height. It is
// drawn only where the sand below it is under the water AND connected to the
// open sea, so a pit dug at the shore fills up to the tide while a hole in the
// middle of the beach stays dry. `terrain_height` is the live sand heightmap and
// `flood_mask` is the sea's flood fill over it.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.15, 0.55, 0.60, 1.0);
// The deep colour stays in the same teal family as the shallows. A navy this
// far from the beach read as a dark maroon band across the horizon, so the open
// water now just gets a little deeper and greener instead of turning black.
uniform vec4 deep_color : source_color = vec4(0.10, 0.36, 0.46, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float shallow_alpha = 0.42;
uniform float deep_alpha = 0.82;
// How deep the water has to be for the foam / the deep colour. Both follow the
// actual water depth, so they work on the open shore and inside a flooded pit.
uniform float foam_depth = 0.30;
uniform float deep_depth = 2.0;
uniform float wave_height = 0.03;

// The sand heightmap (FORMAT_RF, one metre value per texel) and the world
// rectangle it covers.
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform float map_origin = -31.75;
uniform float map_span = 63.5;
// 1 where the sea reaches the sand at the current tide.
uniform sampler2D flood_mask : filter_linear, repeat_disable;
// Current tide height (world Y).
uniform float water_level = -1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float swell = sin(world_pos.x * 0.22 + TIME * 0.9)
		* cos(world_pos.z * 0.17 + TIME * 0.7);
	VERTEX.y += swell * wave_height;
}

// Height of the sand under a world XZ. Outside the heightmap there is no sand:
// open sea past it on the -Z side, solid land on every other side (including the
// beach's flanks, so the water never spills out beside the sand mesh).
float sand_height(vec2 uv) {
	if (uv.y < 0.0) {
		return -100.0;
	}
	if (uv.y > 1.0 || uv.x < 0.0 || uv.x > 1.0) {
		return 100.0;
	}
	return texture(terrain_height, uv).r;
}

void fragment() {
	vec2 uv = (world_pos.xz - vec2(map_origin)) / map_span;
	bool inside = uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
	float ground = sand_height(uv);
	float depth = water_level - ground;
	// Dry sand: no water at all. This is what keeps the flat beach dry.
	if (depth <= 0.01) {
		discard;
	}
	// A hole the tide cannot reach stays dry even when its floor is below sea
	// level: only cells flood-filled from the open sea are drawn.
	if (inside && texture(flood_mask, uv).r < 0.5) {
		discard;
	}

	// 0 at the water's edge, 1 where the water is `deep_depth` metres deep.
	float offshore = clamp(depth / deep_depth, 0.0, 1.0);
	float ripple = sin(world_pos.x * 1.7 + TIME * 2.0)
		* cos(world_pos.z * 1.3 - TIME * 1.6);

	// Foam hugs every edge of the water, the shore and the rim of a flooded pit
	// alike, and pulses gently.
	float foam = 1.0 - smoothstep(0.0, foam_depth, depth);
	foam *= 0.55 + 0.45 * sin(TIME * 2.2 + world_pos.x * 1.3);
	foam = clamp(foam, 0.0, 1.0);

	vec3 color = mix(shallow_color.rgb, deep_color.rgb, offshore);
	color = mix(color, foam_color.rgb, foam);
	ALBEDO = color + ripple * 0.03;
	ALPHA = max(mix(shallow_alpha, deep_alpha, offshore), foam * 0.85);
	ROUGHNESS = mix(0.30, 0.55, foam);
	METALLIC = 0.0;
	SPECULAR = 0.12;
	NORMAL = normalize(NORMAL + vec3(ripple * 0.07, 0.0, ripple * 0.07));

	if (!FRONT_FACING) {
		// Seen from inside the water: a bright, almost solid lid instead of a
		// paper-thin sheet with the sky showing through it.
		ALBEDO = mix(ALBEDO, foam_color.rgb, 0.22);
		ALPHA = clamp(ALPHA + 0.30, 0.0, 0.96);
		NORMAL = -NORMAL;
	}
}
