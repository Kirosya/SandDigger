shader_type spatial;
// Ocean surface. Two meshes share this shader:
//
//  * the beach grid, one vertex per sand cell, which raises every vertex to the
//    water height the flow simulation found for that cell (`water_depth` plus the
//    sand height) - so the surface inside a hole really is down at the water that
//    has run into it, and climbs while it fills;
//  * the open sea beyond the sand, a flat plane at the tide (`use_water_map`
//    off, no simulation out there).
//
// `water_depth` is a FORMAT_RF map of water depth per cell. A value of -1 marks
// open sea, whose surface is simply the tide.
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
// Nothing is drawn shallower than this, which keeps the waterline off the sand.
uniform float edge_depth = 0.02;

// The sand heightmap (FORMAT_RF, one metre value per texel), the undug profile
// it started from, and the world rectangle they cover.
uniform sampler2D terrain_height : filter_linear, repeat_disable;
uniform sampler2D terrain_base : filter_linear, repeat_disable;
uniform float map_origin = -31.75;
uniform float map_span = 63.5;
// Water depth per cell, same rectangle, from the flow simulation.
uniform sampler2D water_depth : filter_linear, repeat_disable;
uniform bool use_water_map = true;
// Current tide height (world Y).
uniform float water_level = -1.0;

varying vec3 world_pos;
varying float surface_y;

// A cell is open sea when it is still plain undug sand under the tide. Anything
// dug is a hole, and only water the flow has actually put there counts.
bool is_open_sea(float ground, float base) {
	return ground < water_level - edge_depth && abs(ground - base) < 0.02;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float surface = water_level;
	if (use_water_map) {
		float ground = texture(terrain_height, UV).r;
		float base = texture(terrain_base, UV).r;
		float depth = texture(water_depth, UV).r;
		if (is_open_sea(ground, base)) {
			surface = water_level;
		} else {
			// A dug cell with no water keeps the sand height, so the surface stays
			// a smooth sheet and the fragment shader cuts the dry cells out.
			surface = depth <= 0.0 ? ground : ground + depth;
		}
	}
	surface_y = surface;
	float swell = sin(world_pos.x * 0.22 + TIME * 0.9)
		* cos(world_pos.z * 0.17 + TIME * 0.7);
	VERTEX.y = surface + swell * wave_height;
}

void fragment() {
	float ground = -100.0;
	if (use_water_map) {
		vec2 uv = (world_pos.xz - vec2(map_origin)) / map_span;
		ground = texture(terrain_height, uv).r;
		float base = texture(terrain_base, uv).r;
		// Only cells the flow actually put water in are drawn, plus the open sea.
		// This is the hard edge of a pool, and it follows the simulated cells
		// instead of the interpolated surface between them.
		if (!is_open_sea(ground, base)
				&& texture(water_depth, uv).r <= edge_depth) {
			discard;
		}
	}
	float depth = surface_y - ground;
	// Dry sand, or a hole the water has not reached: nothing to draw.
	if (depth <= edge_depth) {
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
