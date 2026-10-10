shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;

// Slope blend is in the vertex color: R dry rim, G basalt, B talus, A wet bank.
// Albedo is triplanar where the normal sits between axes, and one tap where it
// does not, so the canyon fill rate stays inside an Intel iGPU.

uniform sampler2D dry_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D bas_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tal_alb : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wet_alb : source_color, filter_linear_mipmap, repeat_enable;

uniform float dry_scale = 0.25;
uniform float bas_scale = 0.42;
uniform float tal_scale = 0.667;
uniform float wet_scale = 0.345;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 masks;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	wpos = wp.xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	masks = COLOR;
}

vec3 sample_alb(sampler2D tex, float scale) {
	// Interpolated normals are shorter than 1, so test the normalized axis.
	vec3 b = abs(normalize(wnorm));
	float top = max(b.x, max(b.y, b.z));
	if (top > 0.8) {
		if (b.y >= b.x && b.y >= b.z) {
			return texture(tex, wpos.xz * scale).rgb;
		}
		if (b.x >= b.z) {
			return texture(tex, wpos.zy * scale).rgb;
		}
		return texture(tex, wpos.xy * scale).rgb;
	}
	b = pow(max(b, vec3(0.001)), vec3(4.0));
	b /= (b.x + b.y + b.z);
	vec3 sx = texture(tex, wpos.zy * scale).rgb;
	vec3 sy = texture(tex, wpos.xz * scale).rgb;
	vec3 sz = texture(tex, wpos.xy * scale).rgb;
	return sx * b.x + sy * b.y + sz * b.z;
}

void fragment() {
	vec4 w = max(masks, vec4(0.0));
	float sum = w.r + w.g + w.b + w.a;
	if (sum < 0.001) {
		w = vec4(1.0, 0.0, 0.0, 0.0);
		sum = 1.0;
	}
	w /= sum;
	vec3 alb = vec3(0.0);
	if (w.r > 0.02) {
		alb += sample_alb(dry_alb, dry_scale) * w.r;
	}
	if (w.g > 0.02) {
		alb += sample_alb(bas_alb, bas_scale) * w.g;
	}
	if (w.b > 0.02) {
		alb += sample_alb(tal_alb, tal_scale) * w.b;
	}
	if (w.a > 0.02) {
		alb += sample_alb(wet_alb, wet_scale) * w.a;
	}
	ALBEDO = alb;
	ROUGHNESS = clamp(dot(w, vec4(0.94, 0.78, 0.97, 0.38)), 0.04, 1.0);
}
