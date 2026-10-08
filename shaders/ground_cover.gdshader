shader_type spatial;
render_mode specular_disabled;

// Flat lots only need one world-XZ sample. Triplanar plus anisotropic
// was resampling this map for every ground pixel on the integrated GPU.
uniform sampler2D alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rgh : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.76, 0.88, 0.67);
uniform float uv_scale = 0.22;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * uv_scale;
	ALBEDO = texture(alb, uv).rgb * tint;
	ROUGHNESS = texture(rgh, uv).r;
	NORMAL_MAP = texture(nrm, uv).rgb;
}
