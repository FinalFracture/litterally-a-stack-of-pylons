shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

// One glass look for the windshield, the rear window, and every door window.
void fragment() {
	ALBEDO = vec3(0.55, 0.70, 0.78);
	METALLIC = 0.0;
	ROUGHNESS = 0.05;
	ALPHA = 0.42;
}
