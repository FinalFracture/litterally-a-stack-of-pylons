shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// One channel for the body shell and every door. The photo keeps panel lines,
// chrome, and lamps. paint_color tints only the pixels marked in the texture alpha.
uniform vec4 paint_color : source_color = vec4(0.25, 0.45, 0.72, 1.0);
uniform sampler2D flank_tex : source_color, filter_linear, repeat_disable;
uniform bool use_photo = false;

void fragment() {
	vec3 shade = COLOR.rgb;
	float mask = COLOR.a;
	vec3 detail = vec3(0.16, 0.16, 0.17);
	if (use_photo) {
		vec4 tex = texture(flank_tex, UV);
		shade = tex.rgb;
		mask = tex.a;
		detail = tex.rgb;
	}
	ALBEDO = mix(detail, paint_color.rgb * shade, mask);
	METALLIC = mix(0.20, 0.42, mask);
	ROUGHNESS = mix(0.46, 0.24, mask);
}
