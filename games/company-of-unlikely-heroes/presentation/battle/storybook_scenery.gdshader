shader_type canvas_item;
render_mode unshaded;

// Field and Gate share the original 1280×820 aperture. Keep the original
// framing at the outer edges and move the aperture (including Gate's wall)
// with the live cells, without resampling a new asset.
const vec2 SOURCE_START = vec2(185.538462, 126.987179) / vec2(1280.0, 820.0);
const vec2 SOURCE_END = vec2(1094.461538, 668.012821) / vec2(1280.0, 820.0);
uniform vec4 aperture;
uniform bool board_scale_wings = false;
uniform vec2 right_fade;

float registered_axis(float p, float low, float high, float source_low, float source_high) {
	if (p < low) {
		return mix(0.0, source_low, p / low);
	}
	if (p > high) {
		return mix(source_high, 1.0, (p - high) / (1.0 - high));
	}
	return mix(source_low, source_high, (p - low) / (high - low));
}

void fragment() {
	if (board_scale_wings) {
		// Continue the aperture's own scale instead of stretching the small
		// authored side wing all the way to the edge of an expanded page.
		vec2 source_uv = SOURCE_START + (UV - aperture.xy)
			* (SOURCE_END - SOURCE_START) / (aperture.zw - aperture.xy);
		vec4 art = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
		// The affine mapping can run past the source at short viewports.
		// Feather those bounds rather than revealing a clamped edge stripe.
		float outside = smoothstep(0.0, 0.02, source_uv.x)
			* (1.0 - smoothstep(0.98, 1.0, source_uv.x))
			* smoothstep(0.0, 0.02, source_uv.y)
			* (1.0 - smoothstep(0.98, 1.0, source_uv.y));
		float right = 1.0 - smoothstep(right_fade.x, right_fade.y, UV.x);
		COLOR = vec4(art.rgb, art.a * outside * right);
	} else {
		vec2 uv = vec2(
			registered_axis(UV.x, aperture.x, aperture.z, SOURCE_START.x, SOURCE_END.x),
			registered_axis(UV.y, aperture.y, aperture.w, SOURCE_START.y, SOURCE_END.y)
		);
		COLOR = texture(TEXTURE, uv);
	}
}
