// Cheap river: depth tint from the depth buffer, two scrolling noise normal maps (flow along +X), fresnel sky reflection. Forward+/Mobile.
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D n1 : hint_normal, repeat_enable; uniform sampler2D n2 : hint_normal, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.16, 0.24, 0.20); uniform vec3 deep : source_color = vec3(0.03, 0.07, 0.08);
uniform float flow = 0.35; uniform float depth_scale = 3.5;
void fragment() {
	float d = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0); v.xyz /= v.w;
	float wd = clamp((VERTEX.z - v.z) / depth_scale, 0.0, 1.0);
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = wpos.xz * 0.035;
	NORMAL_MAP = normalize(texture(n1, uv + vec2(TIME * flow * 0.02, 0.0)).rgb + texture(n2, uv * 1.7 + vec2(TIME * flow * 0.031, 0.013)).rgb);
	NORMAL_MAP_DEPTH = 0.35;
	ALBEDO = mix(shallow, deep, wd); ROUGHNESS = 0.06; METALLIC = 0.0; SPECULAR = 0.6;
	ALPHA = mix(0.75, 0.97, wd);
}
