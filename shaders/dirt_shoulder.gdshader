shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D gravel_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D gravel_rgh : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rocky_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rocky_nrm : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rocky_rgh : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 rocky_tint : source_color = vec3(0.76, 0.88, 0.67);
uniform float shape = 0.0;
uniform float half_w = 4.27;
uniform float feather = 1.02;
uniform float turn_center = 7.93;
uniform float outer_r = 12.2;
uniform float inner_r = 4.07;
uniform float rocky_scale = 0.22;

varying vec2 local_xz;
varying vec3 world_pos;

float shoulder_of(vec2 p) {
	if (shape > 1.5) {
		float box_d = max(abs(p.x - half_w), abs(p.y));
		return smoothstep(half_w - feather, half_w, box_d);
	}
	if (shape > 0.5) {
		float radial = distance(p, vec2(0.0, turn_center));
		float outer_t = smoothstep(outer_r - feather, outer_r, radial);
		float inner_t = smoothstep(inner_r + feather, inner_r, radial);
		return max(outer_t, inner_t);
	}
	return smoothstep(half_w - feather, half_w, abs(p.y));
}

void vertex() {
	local_xz = VERTEX.xz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = clamp(shoulder_of(local_xz), 0.0, 1.0);
	vec2 rocky_uv = world_pos.xz * rocky_scale;
	vec3 gravel_color = texture(gravel_alb, UV).rgb;
	vec3 rocky_color = texture(rocky_alb, rocky_uv).rgb * rocky_tint;
	float gravel_rough = texture(gravel_rgh, UV).r;
	float rocky_rough = texture(rocky_rgh, rocky_uv).r;
	vec3 gravel_normal = texture(gravel_nrm, UV).rgb;
	vec3 rocky_normal = texture(rocky_nrm, rocky_uv).rgb;
	ALBEDO = mix(gravel_color, rocky_color, t);
	ROUGHNESS = mix(gravel_rough, rocky_rough, t);
	NORMAL_MAP = mix(gravel_normal, rocky_normal, t);
}
