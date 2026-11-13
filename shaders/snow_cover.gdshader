shader_type spatial;

uniform sampler2D base_texture : source_color;
uniform bool use_base_texture = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 snow_color : source_color = vec4(0.64, 0.7, 0.8, 1.0);
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 base = base_color.rgb;
	if (use_base_texture) {
		base *= texture(base_texture, UV).rgb;
	}
	ALBEDO = mix(base, snow_color.rgb, snow_amount);
	ROUGHNESS = mix(0.9, 1.0, snow_amount);
}
