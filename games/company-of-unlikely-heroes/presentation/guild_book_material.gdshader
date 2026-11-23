shader_type canvas_item;
render_mode unshaded;

uniform int surface_kind = 0;
uniform vec2 surface_size = vec2(1.0);

float hash_pixel(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 at = fract(p);
	vec2 fade = at * at * (3.0 - 2.0 * at);
	return mix(mix(hash_pixel(cell), hash_pixel(cell + vec2(1.0, 0.0)), fade.x),
		mix(hash_pixel(cell + vec2(0.0, 1.0)), hash_pixel(cell + vec2(1.0)), fade.x), fade.y);
}

float rounded_edge(vec2 p, vec2 extent, float inset, float radius) {
	vec2 dist = abs(p - extent * 0.5) - extent * 0.5 + inset + radius;
	return length(max(dist, 0.0)) + min(max(dist.x, dist.y), 0.0) - radius;
}

float inside(float edge) {
	return 1.0 - smoothstep(-0.65, 0.65, edge);
}

vec3 binding(vec2 p, vec2 extent) {
	float tooth = grain(p * vec2(0.58, 1.08)) - 0.5;
	float mottling = grain(p * 0.021) - 0.5;
	float fold = p.x - extent.x * 0.5;
	float spine = exp(-abs(fold) * 0.11);
	float rise = 3.0 * exp(-abs(fold) * 0.077);
	vec2 leaf_p = vec2(p.x, p.y + sign(p.y - extent.y * 0.5) * rise);

	float leather_edge = rounded_edge(p, extent, 2.2, 14.0);
	vec3 leather = vec3(0.258, 0.158, 0.114) + (tooth * 0.12 + mottling * 0.12);
	leather += 0.17 * exp(-abs(leather_edge + 2.0) * 1.45);
	float along = min(p.y, extent.y - p.y) < min(p.x, extent.x - p.x) ? p.x : p.y;
	float thread = smoothstep(0.26, 0.47, abs(fract(along / 5.4) - 0.5));
	leather = mix(leather, vec3(0.69, 0.45, 0.29),
		thread * exp(-abs(leather_edge + 3.9 + tooth * 0.7) * 2.25) * 0.76);

	float leaf_edge = rounded_edge(leaf_p, extent, 8.4 + tooth * 0.43, 12.0);
	vec3 edges = vec3(0.82, 0.68, 0.48) + tooth * 0.13 + mottling * 0.13;
	edges -= pow(0.5 + 0.5 * sin(leaf_edge * 3.32 + tooth * 0.7), 7.0) * 0.28;

	float paper_edge = rounded_edge(leaf_p, extent, 16.0 + tooth * 0.28, 8.0);
	vec3 paper = vec3(0.978, 0.914, 0.783) + tooth * 0.044 + mottling * 0.042;
	paper -= (vec3(0.13, 0.18, 0.21) + tooth * 0.12) * exp(min(paper_edge, 0.0) * 0.095);
	paper -= vec3(0.23, 0.25, 0.19) * exp(-abs(paper_edge + 0.6) * 1.85);
	paper -= vec3(0.23, 0.26, 0.27) * spine * (fold < 0.0 ? 0.66 : 0.40);
	paper += vec3(0.037, 0.035, 0.019) * exp(-abs(fold - 4.0) * 0.62);

	vec3 bound = mix(vec3(0.113, 0.081, 0.061), leather, inside(leather_edge));
	bound = mix(bound, edges, inside(leaf_edge));
	return mix(bound, paper, inside(paper_edge));
}

vec4 cloth(vec2 p, vec2 extent) {
	float edge = rounded_edge(p, extent, 0.8, 5.0);
	float weave = sin(p.x * 3.0) * sin(p.y * 3.3) * 0.032;
	float nap = (grain(p * vec2(0.86, 0.40)) - 0.5) * 0.047;
	float worn = (grain(p * 0.033) - 0.5) * 0.049;
	vec3 green = vec3(0.092, 0.212, 0.163) + weave + nap + worn;
	green -= exp(min(edge, 0.0) * 0.17) * 0.045;
	green = mix(green, vec3(0.69, 0.50, 0.29) + nap, exp(-abs(edge + 0.8) * 1.6));

	vec2 corner = min(p, extent - p) - 16.0;
	float distance = length(corner);
	float rivet = inside(distance - 7.7);
	float shadow = 1.0 - smoothstep(7.0, 11.0, length(corner - vec2(0.9, 1.6)));
	vec3 metal = mix(vec3(0.38, 0.22, 0.09), vec3(0.86, 0.64, 0.30), clamp(1.4 - distance * 0.13, 0.0, 1.0));
	metal += 0.20 * exp(-length(corner - vec2(-2.4, -3.0)) * 0.7);
	green = mix(green * (1.0 - shadow * 0.55), metal + nap, rivet);
	return vec4(green, inside(edge));
}

vec4 posting(vec2 p, vec2 extent) {
	float tooth = grain(p * vec2(0.65, 1.14)) - 0.5;
	float mottling = grain(p * 0.044) - 0.5;
	float corners = rounded_edge(p, extent, 3.0 + mottling * 2.7 + tooth * 0.6, 9.0);
	vec2 fold = vec2(extent.x - p.x - 3.0, p.y - 3.0);
	float clipped = (27.0 - fold.x - fold.y) * 0.707;
	float edge = max(corners, clipped);
	float shade = 1.0 - smoothstep(0.0, 5.0, rounded_edge(p - vec2(0.2, 2.4), extent, 3.0, 9.0));
	shade *= 1.0 - smoothstep(0.0, 5.0, clipped - 1.0);

	vec3 page = vec3(0.985, 0.919, 0.796) + tooth * 0.035 + mottling * 0.034;
	page -= vec3(0.12, 0.16, 0.17) * exp(min(corners, 0.0) * 0.14);
	page += vec3(0.05, 0.08, 0.11) * exp(-abs(corners + 1.0) * 1.3);
	page -= vec3(0.19, 0.20, 0.17) * exp(-abs(corners - 0.5) * 1.2);

	float dogear = min(fold.x, 27.0) - 20.0 + fold.y * 0.19;
	float bent = inside(dogear) * (1.0 - smoothstep(25.5, 29.5, fold.y)) * inside(edge);
	page -= vec3(0.17, 0.20, 0.22) * exp(-abs(dogear - 0.7) * 0.58) * (1.0 - smoothstep(24.0, 34.0, fold.y));
	page = mix(page, vec3(0.96, 0.86, 0.68) + fold.x * 0.005 + tooth * 0.045, bent);

	vec2 pin = p - vec2(20.0, 15.0);
	float pin_size = length(pin);
	float pin_edge = inside(pin_size - 7.3);
	float pin_shadow = 1.0 - smoothstep(5.3, 10.5, length(pin - vec2(0.6, 1.6)));
	vec3 brass = mix(vec3(0.33, 0.21, 0.088), vec3(0.86, 0.62, 0.29), clamp(1.7 - pin_size * 0.22, 0.0, 1.0));
	brass += exp(-length(pin + vec2(2.0, 2.6)) * 0.49) * 0.44;
	page = mix(page - vec3(0.35, 0.35, 0.30) * pin_shadow, brass, pin_edge);
	float sheet = inside(edge);
	return vec4(mix(vec3(0.28, 0.16, 0.07), page, sheet), max(sheet, shade * 0.36));
}

void fragment() {
	vec2 p = UV * surface_size;
	if (surface_kind == 2) {
		COLOR = posting(p, surface_size);
	} else if (surface_kind == 1) {
		COLOR = cloth(p, surface_size);
	} else {
		COLOR = vec4(binding(p, surface_size), 1.0);
	}
}
