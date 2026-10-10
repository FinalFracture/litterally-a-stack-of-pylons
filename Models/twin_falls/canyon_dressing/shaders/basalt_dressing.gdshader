// tf_basalt_dressing: near-black basalt, world triplanar (cliff_side luminance + detail at a second scale to break tiling),
// vertex colour R = warm desert varnish, G = pale mineral / lichen streak, B = wet (seeps, river boulders).
shader_type spatial;
uniform sampler2D rock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_col : source_color = vec3(0.052, 0.050, 0.048);
uniform vec3 varnish_col : source_color = vec3(0.085, 0.060, 0.042);
uniform vec3 lichen_col : source_color = vec3(0.30, 0.30, 0.27);
uniform float s1 = 0.33; uniform float s2 = 0.071;
varying vec3 wp; varying vec3 wn;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
float lum(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }
vec4 tri(sampler2D t, float s) {
	vec3 b = pow(abs(wn), vec3(4.0)); b /= (b.x + b.y + b.z);
	return texture(t, wp.zy * s) * b.x + texture(t, wp.xz * s) * b.y + texture(t, wp.xy * s) * b.z;
}
void fragment() {
	float d = lum(tri(rock, s1).rgb) * 1.6 * (0.6 + 0.8 * lum(tri(rock, s2).rgb));
	vec3 c = mix(base_col, varnish_col, COLOR.r) * (0.55 + d);
	float streak = COLOR.g * smoothstep(0.35, 0.65, d + 0.2 * sin(wp.y * 1.7));
	c = mix(c, lichen_col * (0.6 + 0.5 * d), streak);
	c *= mix(1.0, 0.55, COLOR.b);
	ALBEDO = c; ROUGHNESS = mix(0.88, 0.25, COLOR.b);
	vec3 n = tri(rock_n, s1).rgb; NORMAL_MAP = n; NORMAL_MAP_DEPTH = 0.9;
}
