shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

uniform vec4 snow_color : source_color = vec4(0.64, 0.7, 0.8, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 snow_world_normal;

void vertex() {
	snow_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float upward_coverage = smoothstep(0.7, 0.9, snow_world_normal.y);
	ALBEDO = snow_color.rgb;
	ALPHA = upward_coverage * snow_amount;
}
