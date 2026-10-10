// Test stand-in for the in-game terrain: our terrain set blended triplanar by slope (dirt flat, talus mid, basalt steep, wet bank near the water).
shader_type spatial;
uniform sampler2D dirt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D talus : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D basalt : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D n_rock : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float s_dirt = 0.25; uniform float s_talus = 0.667; uniform float s_basalt = 0.1667; uniform float s_wet = 0.345;
uniform float water_y = 0.0;
varying vec3 wp; varying vec3 wn;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
vec3 tri(sampler2D t, float s) {
	vec3 b = pow(abs(wn), vec3(4.0)); b /= (b.x + b.y + b.z);
	return texture(t, wp.zy * s).rgb * b.x + texture(t, wp.xz * s).rgb * b.y + texture(t, wp.xy * s).rgb * b.z;
}
void fragment() {
	float up = wn.y;
	vec3 c_d = tri(dirt, s_dirt), c_t = tri(talus, s_talus), c_b = tri(basalt, s_basalt), c_w = tri(wet, s_wet);
	float w_steep = smoothstep(0.62, 0.42, up); float w_flat = smoothstep(0.82, 0.92, up);
	vec3 c = mix(mix(c_t, c_d, w_flat), c_b, w_steep);
	float wetk = smoothstep(2.5, 0.3, wp.y - water_y);
	c = mix(c, c_w * 0.8, wetk * (1.0 - w_steep * 0.5));
	ALBEDO = c; ROUGHNESS = mix(0.95, 0.35, wetk);
}
