shader_type spatial;

uniform sampler2D base_texture : source_color;
uniform bool use_base_texture = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 snow_color : source_color = vec4(0.64, 0.7, 0.8, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform bool snow_upward_only = false;

varying vec3 snow_world_normal;

void vertex() {
	snow_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = base_color.rgb;
	if (use_base_texture) {
		base *= texture(base_texture, UV).rgb;
	}

	float coverage = snow_amount;
	if (snow_upward_only) {
		coverage *= smoothstep(0.65, 0.85, snow_world_normal.y);
	}

	ALBEDO = mix(base, snow_color.rgb, coverage);
	ROUGHNESS = mix(0.9, 1.0, coverage);
}
