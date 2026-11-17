shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform vec4 sheen_color : source_color = vec4(1.0, 0.96, 0.75, 1.0);
uniform float sweep_speed : hint_range(0.5, 5.0) = 1.8;
uniform float band_width : hint_range(0.05, 1.0) = 0.22;
uniform float intensity : hint_range(0.1, 3.0) = 1.35;

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    float coord = local_pos.x * 0.6 + local_pos.z * 0.8 + local_pos.y * 0.4;
    float sweep_pos = mod(TIME * sweep_speed, 5.0) - 2.5;
    float dist = abs(coord - sweep_pos);
    float band = smoothstep(band_width, 0.0, dist);
    float trail = smoothstep(
        band_width * 0.5,
        0.0,
        abs(coord - (sweep_pos - band_width * 1.4))
    ) * 0.5;

    float glow = (band + trail) * intensity;
    ALBEDO = sheen_color.rgb * glow;
    ALPHA = clamp(glow, 0.0, 1.0);
}
